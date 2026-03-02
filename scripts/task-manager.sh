#!/usr/bin/env bash
set -euo pipefail

SCHEDULER_DIR="${HOME}/.claude-scheduler"
TASKS_DIR="${SCHEDULER_DIR}/tasks"
LOGS_DIR="${SCHEDULER_DIR}/logs"

ensure_dirs() {
  mkdir -p "$TASKS_DIR" "$LOGS_DIR"
}

generate_id() {
  head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

find_python() {
  if command -v python3 &>/dev/null; then
    echo "python3"
  elif command -v python &>/dev/null; then
    echo "python"
  else
    echo "Error: Python 3 is required but not found in PATH" >&2
    exit 1
  fi
}

PYTHON="$(find_python)"

# --- create ---
cmd_create() {
  local name="" schedule="" schedule_human="" working_dir="" prompt=""
  local allowed_tools="Read,Grep,Glob" max_turns=10 notify=true one_shot=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)         name="$2";          shift 2 ;;
      --schedule)     schedule="$2";      shift 2 ;;
      --schedule-human) schedule_human="$2"; shift 2 ;;
      --working-dir)  working_dir="$2";   shift 2 ;;
      --prompt)       prompt="$2";        shift 2 ;;
      --allowed-tools) allowed_tools="$2"; shift 2 ;;
      --max-turns)    max_turns="$2";     shift 2 ;;
      --notify)       notify="$2";        shift 2 ;;
      --one-shot)     one_shot="$2";      shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$name" || -z "$schedule" || -z "$prompt" ]]; then
    echo '{"error": "Required: --name, --schedule, --prompt"}' >&2
    exit 1
  fi

  [[ -z "$working_dir" ]] && working_dir="$(pwd)"
  [[ -z "$schedule_human" ]] && schedule_human="$schedule"

  ensure_dirs
  local id
  id="$(generate_id)"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local task_file="${TASKS_DIR}/${id}.json"

  $PYTHON -c "
import json, sys
task = {
    'id': sys.argv[1],
    'name': sys.argv[2],
    'schedule': sys.argv[3],
    'schedule_human': sys.argv[4],
    'working_directory': sys.argv[5],
    'prompt': sys.argv[6],
    'allowed_tools': sys.argv[7],
    'max_turns': int(sys.argv[8]),
    'notify': sys.argv[9].lower() == 'true',
    'one_shot': sys.argv[10].lower() == 'true',
    'created_at': sys.argv[11],
    'updated_at': sys.argv[11],
    'status': 'active'
}
with open(sys.argv[12], 'w') as f:
    json.dump(task, f, indent=2)
print(json.dumps(task, indent=2))
" "$id" "$name" "$schedule" "$schedule_human" "$working_dir" "$prompt" \
  "$allowed_tools" "$max_turns" "$notify" "$one_shot" "$now" "$task_file"
}

# --- list ---
cmd_list() {
  local format="json" status_filter="all"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --format) format="$2"; shift 2 ;;
      --status) status_filter="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  ensure_dirs

  if [[ "$format" == "table" ]]; then
    $PYTHON -c "
import json, glob, os, sys

tasks_dir = sys.argv[1]
status_filter = sys.argv[2]
files = sorted(glob.glob(os.path.join(tasks_dir, '*.json')))
tasks = []
for f in files:
    with open(f) as fh:
        t = json.load(fh)
        if status_filter == 'all' or t.get('status') == status_filter:
            tasks.append(t)

if not tasks:
    print('No scheduled tasks.')
    sys.exit(0)

print(f\"{'ID':<10} {'Status':<8} {'Schedule':<22} {'Name'}\")
print('-' * 70)
for t in tasks:
    print(f\"{t['id']:<10} {t['status']:<8} {t['schedule_human']:<22} {t['name']}\")
print(f\"\n{len(tasks)} task(s) total.\")
" "$TASKS_DIR" "$status_filter"
  else
    $PYTHON -c "
import json, glob, os, sys

tasks_dir = sys.argv[1]
status_filter = sys.argv[2]
files = sorted(glob.glob(os.path.join(tasks_dir, '*.json')))
tasks = []
for f in files:
    with open(f) as fh:
        t = json.load(fh)
        if status_filter == 'all' or t.get('status') == status_filter:
            tasks.append(t)
print(json.dumps(tasks, indent=2))
" "$TASKS_DIR" "$status_filter"
  fi
}

# --- get ---
cmd_get() {
  local id="$1"
  local task_file="${TASKS_DIR}/${id}.json"

  if [[ ! -f "$task_file" ]]; then
    echo "{\"error\": \"Task not found: ${id}\"}" >&2
    exit 1
  fi

  $PYTHON -c "
import json, sys
with open(sys.argv[1]) as f:
    print(json.dumps(json.load(f), indent=2))
" "$task_file"
}

# --- update ---
cmd_update() {
  local id="$1"; shift
  local task_file="${TASKS_DIR}/${id}.json"

  if [[ ! -f "$task_file" ]]; then
    echo "{\"error\": \"Task not found: ${id}\"}" >&2
    exit 1
  fi

  # Collect update fields as key/value argv pairs
  local updates=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)          updates+=("name" "$2");             shift 2 ;;
      --schedule)      updates+=("schedule" "$2");         shift 2 ;;
      --schedule-human) updates+=("schedule_human" "$2");  shift 2 ;;
      --working-dir)   updates+=("working_directory" "$2"); shift 2 ;;
      --prompt)        updates+=("prompt" "$2");           shift 2 ;;
      --allowed-tools) updates+=("allowed_tools" "$2");    shift 2 ;;
      --max-turns)     updates+=("max_turns" "$2");        shift 2 ;;
      --notify)        updates+=("notify" "$2");           shift 2 ;;
      --status)        updates+=("status" "$2");           shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  $PYTHON -c "
import json, sys, os
from datetime import datetime, timezone

task_file = sys.argv[1]
raw = sys.argv[2:]

with open(task_file) as f:
    task = json.load(f)

if len(raw) % 2 != 0:
    print('{\"error\": \"Invalid update arguments\"}', file=sys.stderr)
    sys.exit(1)

for i in range(0, len(raw), 2):
    key = raw[i]
    val = raw[i + 1]
    if key == 'max_turns':
        val = int(val)
    elif key == 'notify':
        val = val.lower() == 'true'
    task[key] = val

task['updated_at'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

tmp = task_file + '.tmp'
with open(tmp, 'w') as f:
    json.dump(task, f, indent=2)
os.rename(tmp, task_file)

print(json.dumps(task, indent=2))
" "$task_file" "${updates[@]}"
}

# --- delete ---
cmd_delete() {
  local id="$1"
  local task_file="${TASKS_DIR}/${id}.json"

  if [[ ! -f "$task_file" ]]; then
    echo "{\"error\": \"Task not found: ${id}\"}" >&2
    exit 1
  fi

  rm -f "$task_file"
  rm -rf "${LOGS_DIR}/${id}"
  echo "{\"id\": \"${id}\", \"deleted\": true}"
}

# --- main ---
if [[ $# -lt 1 ]]; then
  echo "Usage: task-manager.sh {create|list|get|update|delete} [options]" >&2
  exit 1
fi

command="$1"; shift

case "$command" in
  create) cmd_create "$@" ;;
  list)   cmd_list "$@" ;;
  get)    cmd_get "$@" ;;
  update) cmd_update "$@" ;;
  delete) cmd_delete "$@" ;;
  *)
    echo "Unknown command: $command" >&2
    echo "Usage: task-manager.sh {create|list|get|update|delete} [options]" >&2
    exit 1
    ;;
esac
