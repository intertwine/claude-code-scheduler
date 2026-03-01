#!/usr/bin/env bash
set -euo pipefail

# Execution wrapper invoked by launchd/cron.
# Reads a task definition, runs claude -p, logs output, sends notification.

# Ensure common paths are available (launchd/cron have minimal PATH)
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${HOME}/.local/bin:${HOME}/.npm-global/bin:${PATH}"

SCHEDULER_DIR="${HOME}/.claude-scheduler"
TASKS_DIR="${SCHEDULER_DIR}/tasks"
LOGS_DIR="${SCHEDULER_DIR}/logs"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: run-task.sh <task-id>" >&2
  exit 1
fi

task_id="$1"
task_file="${TASKS_DIR}/${task_id}.json"

if [[ ! -f "$task_file" ]]; then
  echo "Error: Task not found: ${task_id}" >&2
  exit 1
fi

# Find Python
PYTHON="python3"
command -v python3 &>/dev/null || PYTHON="python"
command -v "$PYTHON" &>/dev/null || { echo "Error: Python 3 required" >&2; exit 1; }

# Parse task JSON
read_field() {
  $PYTHON -c "import json,sys; t=json.load(open(sys.argv[1])); print(t.get(sys.argv[2], sys.argv[3]))" "$task_file" "$1" "${2:-}"
}

status="$(read_field status "")"
if [[ "$status" != "active" ]]; then
  echo "Task ${task_id} is ${status}, skipping." >&2
  exit 0
fi

name="$(read_field name "unnamed")"
working_dir="$(read_field working_directory "$(pwd)")"
prompt="$(read_field prompt "")"
allowed_tools="$(read_field allowed_tools "Read,Grep,Glob")"
max_turns="$(read_field max_turns 10)"
notify="$(read_field notify True)"
notify_enabled=false
if [[ "$notify" == "True" || "$notify" == "true" ]]; then
  notify_enabled=true
fi

if [[ -z "$prompt" ]]; then
  echo "Error: Task ${task_id} has empty prompt" >&2
  exit 1
fi

# Verify working directory exists
if [[ ! -d "$working_dir" ]]; then
  if [[ "$notify_enabled" == "true" ]]; then
    "${SCRIPT_DIR}/notify.sh" --title "Claude Scheduler" \
      --message "Task '${name}' failed: directory not found: ${working_dir}" --failure
  fi
  echo "Error: directory not found: ${working_dir}" >&2
  exit 1
fi

# Verify claude CLI is available
if ! command -v claude &>/dev/null; then
  if [[ "$notify_enabled" == "true" ]]; then
    "${SCRIPT_DIR}/notify.sh" --title "Claude Scheduler" \
      --message "Task '${name}' failed: claude CLI not found in PATH" --failure
  fi
  echo "Error: claude CLI not found in PATH" >&2
  exit 1
fi

# Set up logging
log_dir="${LOGS_DIR}/${task_id}"
mkdir -p "$log_dir"
timestamp="$(date +%Y%m%d_%H%M%S)"
log_file="${log_dir}/${timestamp}.log"

# Log header
{
  echo "=== Claude Scheduler Task Execution ==="
  echo "Task:    ${name} (${task_id})"
  echo "Time:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Dir:     ${working_dir}"
  echo "Prompt:  ${prompt}"
  echo "Tools:   ${allowed_tools}"
  echo "Turns:   ${max_turns}"
  echo "======================================="
  echo ""
} > "$log_file"

# Execute claude
exit_code=0
cd "$working_dir"
claude -p "$prompt" \
  --allowedTools "$allowed_tools" \
  --max-turns "$max_turns" \
  --output-format text \
  >> "$log_file" 2>&1 || exit_code=$?

# Log footer
{
  echo ""
  echo "======================================="
  echo "Exit code: ${exit_code}"
  echo "Finished:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "======================================="
} >> "$log_file"

# Update latest symlink
ln -sf "${timestamp}.log" "${log_dir}/latest"

# Send notification
if [[ "$notify_enabled" == "true" ]]; then
  if [[ $exit_code -eq 0 ]]; then
    "${SCRIPT_DIR}/notify.sh" --title "Claude Scheduler" \
      --message "Task '${name}' completed successfully" --success
  else
    "${SCRIPT_DIR}/notify.sh" --title "Claude Scheduler" \
      --message "Task '${name}' failed (exit code ${exit_code})" --failure
  fi
fi

exit $exit_code
