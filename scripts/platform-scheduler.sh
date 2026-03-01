#!/usr/bin/env bash
set -euo pipefail

# Platform-specific scheduler registration.
# macOS: launchd plists in ~/Library/LaunchAgents/
# Linux: crontab entries with marker comments

SCHEDULER_DIR="${HOME}/.claude-scheduler"
TASKS_DIR="${SCHEDULER_DIR}/tasks"
LOGS_DIR="${SCHEDULER_DIR}/logs"

# Resolve the absolute path to the scripts directory (where run-task.sh lives)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PLIST_PREFIX="com.claude-scheduler"
CRONTAB_MARKER="claude-scheduler"

# Find Python
PYTHON="python3"
command -v python3 &>/dev/null || PYTHON="python"
command -v "$PYTHON" &>/dev/null || { echo '{"error": "Python 3 required"}' >&2; exit 1; }

detect_platform() {
  case "$(uname -s)" in
    Darwin) echo "darwin" ;;
    Linux)  echo "linux" ;;
    *)
      echo '{"error": "Unsupported platform: '"$(uname -s)"'. Only macOS and Linux are supported."}' >&2
      exit 1
      ;;
  esac
}

# --- macOS: launchd ---

plist_path() {
  echo "${HOME}/Library/LaunchAgents/${PLIST_PREFIX}.$1.plist"
}

generate_plist() {
  local task_id="$1"
  local task_file="${TASKS_DIR}/${task_id}.json"

  $PYTHON - "$task_id" "$task_file" "$SCRIPT_DIR" "$LOGS_DIR" "$PLIST_PREFIX" "$HOME" << 'PYEOF'
import json, sys, os

task_id = sys.argv[1]
task_file = sys.argv[2]
script_dir = sys.argv[3]
logs_dir = sys.argv[4]
plist_prefix = sys.argv[5]
home = sys.argv[6]

with open(task_file) as f:
    task = json.load(f)

cron = task['schedule'].split()
if len(cron) != 5:
    print(f'{{"error": "Invalid cron expression: {task["schedule"]}. Must have 5 fields."}}', file=sys.stderr)
    sys.exit(1)

minute, hour, day, month, weekday = cron

def parse_field(field, key):
    """Convert a cron field to a list of launchd StartCalendarInterval dicts."""
    if field == '*':
        return [{}]

    values = []
    for part in field.split(','):
        if '/' in part:
            # Step values: */15 or 0-30/5
            base, step = part.split('/')
            step = int(step)
            if base == '*':
                if key == 'Minute':
                    rng = range(0, 60, step)
                elif key == 'Hour':
                    rng = range(0, 24, step)
                elif key == 'Day':
                    rng = range(1, 32, step)
                elif key == 'Month':
                    rng = range(1, 13, step)
                elif key == 'Weekday':
                    rng = range(0, 7, step)
                else:
                    rng = range(0, 60, step)
            else:
                lo, hi = base.split('-') if '-' in base else (base, base)
                rng = range(int(lo), int(hi) + 1, step)
            values.extend(rng)
        elif '-' in part:
            lo, hi = part.split('-')
            values.extend(range(int(lo), int(hi) + 1))
        else:
            values.append(int(part))

    return [{key: v} for v in values]

# Build all possible calendar interval combinations.
# Cron semantics for day-of-month and day-of-week are OR when both are restricted.
minute_entries = parse_field(minute, 'Minute')
hour_entries = parse_field(hour, 'Hour')
day_entries = parse_field(day, 'Day')
month_entries = parse_field(month, 'Month')
weekday_entries = parse_field(weekday, 'Weekday')

# Compose day constraints with cron-compatible OR semantics.
if day == '*' and weekday == '*':
    day_week_entries = [{}]
elif day == '*':
    day_week_entries = weekday_entries
elif weekday == '*':
    day_week_entries = day_entries
else:
    day_week_entries = day_entries + weekday_entries

# Merge into combined intervals
intervals = []
seen = set()
for mi in minute_entries:
    for hi in hour_entries:
        for mo in month_entries:
            for dw in day_week_entries:
                merged = {}
                merged.update(mi)
                merged.update(hi)
                merged.update(mo)
                merged.update(dw)
                key = tuple(sorted(merged.items()))
                if key in seen:
                    continue
                seen.add(key)
                intervals.append(merged)

# Cap at 100 intervals to prevent absurd plists
if len(intervals) > 100:
    print(f'{{"error": "Cron expression generates {len(intervals)} intervals (max 100). Simplify the schedule."}}', file=sys.stderr)
    sys.exit(1)

# Build calendar interval XML
def interval_xml(interval):
    lines = ['        <dict>']
    for key, val in sorted(interval.items()):
        lines.append(f'            <key>{key}</key>')
        lines.append(f'            <integer>{val}</integer>')
    lines.append('        </dict>')
    return '\n'.join(lines)

if len(intervals) == 1:
    cal_xml = '    <key>StartCalendarInterval</key>\n' + interval_xml(intervals[0])
else:
    inner = '\n'.join(interval_xml(i) for i in intervals)
    cal_xml = f'    <key>StartCalendarInterval</key>\n    <array>\n{inner}\n    </array>'

log_dir = os.path.join(logs_dir, task_id)
os.makedirs(log_dir, exist_ok=True)

# Build PATH including common locations
path_val = f"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:{home}/.local/bin:{home}/.npm-global/bin"

plist = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{plist_prefix}.{task_id}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>{script_dir}/run-task.sh</string>
        <string>{task_id}</string>
    </array>
{cal_xml}
    <key>StandardOutPath</key>
    <string>{log_dir}/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>{log_dir}/launchd-stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>{path_val}</string>
        <key>HOME</key>
        <string>{home}</string>
    </dict>
</dict>
</plist>'''

print(plist)
PYEOF
}

register_launchd() {
  local task_id="$1"
  local plist
  plist="$(plist_path "$task_id")"
  local log_dir="${LOGS_DIR}/${task_id}"

  mkdir -p "$(dirname "$plist")" "$log_dir"

  # Generate and write plist
  generate_plist "$task_id" > "$plist"

  # Validate plist
  if ! plutil -lint "$plist" &>/dev/null; then
    echo '{"error": "Generated plist failed validation"}' >&2
    rm -f "$plist"
    exit 1
  fi

  # Unload first if already loaded (ignore errors)
  launchctl unload "$plist" 2>/dev/null || true

  # Load the plist
  launchctl load "$plist"

  echo "{\"task_id\": \"${task_id}\", \"platform\": \"darwin\", \"registered\": true, \"plist\": \"${plist}\"}"
}

unregister_launchd() {
  local task_id="$1"
  local plist
  plist="$(plist_path "$task_id")"

  if [[ -f "$plist" ]]; then
    launchctl unload "$plist" 2>/dev/null || true
    rm -f "$plist"
  fi

  echo "{\"task_id\": \"${task_id}\", \"platform\": \"darwin\", \"unregistered\": true}"
}

status_launchd() {
  local task_id="$1"
  local plist
  plist="$(plist_path "$task_id")"
  local label="${PLIST_PREFIX}.${task_id}"

  local registered=false
  local loaded=false

  [[ -f "$plist" ]] && registered=true
  launchctl list "$label" &>/dev/null && loaded=true

  echo "{\"task_id\": \"${task_id}\", \"platform\": \"darwin\", \"registered\": ${registered}, \"loaded\": ${loaded}}"
}

# --- Linux: crontab ---

register_crontab() {
  local task_id="$1"
  local task_file="${TASKS_DIR}/${task_id}.json"

  local schedule
  schedule="$($PYTHON -c "import json,sys; print(json.load(open(sys.argv[1]))['schedule'])" "$task_file")"

  # Remove existing entry if present
  unregister_crontab "$task_id" > /dev/null 2>&1 || true

  local run_script="${SCRIPT_DIR}/run-task.sh"
  local log_dir="${LOGS_DIR}/${task_id}"
  mkdir -p "$log_dir"

  # Add new crontab entry
  local entry="${schedule} /bin/bash ${run_script} ${task_id} >> ${log_dir}/cron.log 2>&1 #${CRONTAB_MARKER}:${task_id}"

  (crontab -l 2>/dev/null; echo "$entry") | crontab -

  echo "{\"task_id\": \"${task_id}\", \"platform\": \"linux\", \"registered\": true}"
}

unregister_crontab() {
  local task_id="$1"

  crontab -l 2>/dev/null | grep -v "#${CRONTAB_MARKER}:${task_id}" | crontab - 2>/dev/null || true

  echo "{\"task_id\": \"${task_id}\", \"platform\": \"linux\", \"unregistered\": true}"
}

status_crontab() {
  local task_id="$1"

  local registered=false
  if crontab -l 2>/dev/null | grep -q "#${CRONTAB_MARKER}:${task_id}"; then
    registered=true
  fi

  echo "{\"task_id\": \"${task_id}\", \"platform\": \"linux\", \"registered\": ${registered}}"
}

# --- dispatch ---

cmd_register() {
  local task_id="$1"
  local task_file="${TASKS_DIR}/${task_id}.json"

  if [[ ! -f "$task_file" ]]; then
    echo "{\"error\": \"Task not found: ${task_id}\"}" >&2
    exit 1
  fi

  local platform
  platform="$(detect_platform)"

  case "$platform" in
    darwin) register_launchd "$task_id" ;;
    linux)  register_crontab "$task_id" ;;
  esac
}

cmd_unregister() {
  local task_id="$1"

  local platform
  platform="$(detect_platform)"

  case "$platform" in
    darwin) unregister_launchd "$task_id" ;;
    linux)  unregister_crontab "$task_id" ;;
  esac
}

cmd_status() {
  local task_id="$1"

  local platform
  platform="$(detect_platform)"

  case "$platform" in
    darwin) status_launchd "$task_id" ;;
    linux)  status_crontab "$task_id" ;;
  esac
}

cmd_status_all() {
  local platform
  platform="$(detect_platform)"

  echo "["
  local first=true
  for task_file in "${TASKS_DIR}"/*.json; do
    [[ -f "$task_file" ]] || continue
    local task_id
    task_id="$(basename "$task_file" .json)"

    [[ "$first" == "true" ]] || echo ","
    first=false

    case "$platform" in
      darwin) status_launchd "$task_id" ;;
      linux)  status_crontab "$task_id" ;;
    esac
  done
  echo "]"
}

# --- main ---
if [[ $# -lt 1 ]]; then
  echo "Usage: platform-scheduler.sh {register|unregister|status|status-all} [task-id]" >&2
  exit 1
fi

command="$1"; shift

case "$command" in
  register)    cmd_register "$1" ;;
  unregister)  cmd_unregister "$1" ;;
  status)      cmd_status "$1" ;;
  status-all)  cmd_status_all ;;
  *)
    echo "Unknown command: $command" >&2
    exit 1
    ;;
esac
