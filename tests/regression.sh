#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_MANAGER="${ROOT_DIR}/scripts/task-manager.sh"
PLATFORM_SCHEDULER="${ROOT_DIR}/scripts/platform-scheduler.sh"
RUN_TASK="${ROOT_DIR}/scripts/run-task.sh"

find_python() {
  if command -v python3 &>/dev/null; then
    echo "python3"
  elif command -v python &>/dev/null; then
    echo "python"
  else
    echo "Error: Python 3 required" >&2
    exit 1
  fi
}

PYTHON="$(find_python)"

TMP_DIRS=()

cleanup() {
  for dir in "${TMP_DIRS[@]-}"; do
    rm -rf "$dir"
  done
}

trap cleanup EXIT

new_tmp_home() {
  local dir
  dir="$(mktemp -d)"
  TMP_DIRS+=("$dir")
  echo "$dir"
}

read_json_field() {
  local json_file="$1"
  local field="$2"
  "$PYTHON" -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$json_file" "$field"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local context="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: Expected '${needle}' in ${context}" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local context="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "FAIL: Did not expect '${needle}' in ${context}" >&2
    exit 1
  fi
}

test_multiline_update_preserved() {
  local home task_id expected actual
  home="$(new_tmp_home)"

  HOME="$home" "$TASK_MANAGER" create \
    --name "Multiline update test" \
    --schedule "* * * * *" \
    --working-dir "$ROOT_DIR" \
    --prompt "initial" \
    > "${home}/create.json"
  task_id="$(read_json_field "${home}/create.json" "id")"

  expected=$'first line\nsecond line\nthird line'
  HOME="$home" "$TASK_MANAGER" update "$task_id" --prompt "$expected" > /dev/null
  actual="$(HOME="$home" "$TASK_MANAGER" get "$task_id" | "$PYTHON" -c "import json,sys; print(json.load(sys.stdin)['prompt'])")"

  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: Multiline prompt was not preserved on update" >&2
    exit 1
  fi

  echo "PASS: multiline update preserved"
}

test_notify_false_suppresses_preflight_notifications() {
  local home task_id output rc
  home="$(new_tmp_home)"

  HOME="$home" "$TASK_MANAGER" create \
    --name "Notify false preflight test" \
    --schedule "* * * * *" \
    --working-dir "${home}/missing-directory" \
    --prompt "noop" \
    --notify false \
    > "${home}/create.json"
  task_id="$(read_json_field "${home}/create.json" "id")"

  set +e
  output="$(HOME="$home" "$RUN_TASK" "$task_id" 2>&1)"
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "FAIL: run-task should fail for missing working directory" >&2
    exit 1
  fi

  assert_contains "$output" "directory not found" "run-task stderr"
  assert_not_contains "$output" "[notify]" "run-task stderr"

  echo "PASS: notify=false suppresses preflight notifications"
}

test_launchd_dom_dow_or_semantics() {
  local home task_id plist
  home="$(new_tmp_home)"

  HOME="$home" "$TASK_MANAGER" create \
    --name "launchd OR semantics test" \
    --schedule "0 9 1 * 1" \
    --working-dir "$ROOT_DIR" \
    --prompt "noop" \
    > "${home}/create.json"
  task_id="$(read_json_field "${home}/create.json" "id")"

  HOME="$home" "$PLATFORM_SCHEDULER" register "$task_id" > /dev/null
  plist="${home}/Library/LaunchAgents/com.claude-scheduler.${task_id}.plist"

  if [[ ! -f "$plist" ]]; then
    echo "FAIL: Expected plist at ${plist}" >&2
    exit 1
  fi

  "$PYTHON" - "$plist" << 'PYEOF'
import plistlib
import sys

plist_path = sys.argv[1]
with open(plist_path, "rb") as f:
    data = plistlib.load(f)

intervals = data.get("StartCalendarInterval")
if isinstance(intervals, dict):
    intervals = [intervals]

if not isinstance(intervals, list) or not intervals:
    print("FAIL: StartCalendarInterval is empty or invalid", file=sys.stderr)
    sys.exit(1)

day_only = any(
    i.get("Minute") == 0
    and i.get("Hour") == 9
    and i.get("Day") == 1
    and "Weekday" not in i
    for i in intervals
)
weekday_only = any(
    i.get("Minute") == 0
    and i.get("Hour") == 9
    and i.get("Weekday") == 1
    and "Day" not in i
    for i in intervals
)
day_and_weekday = any(
    i.get("Minute") == 0
    and i.get("Hour") == 9
    and i.get("Day") == 1
    and i.get("Weekday") == 1
    for i in intervals
)

if not day_only or not weekday_only or day_and_weekday:
    print("FAIL: launchd intervals do not represent cron OR semantics", file=sys.stderr)
    print(intervals, file=sys.stderr)
    sys.exit(1)
PYEOF

  HOME="$home" "$PLATFORM_SCHEDULER" unregister "$task_id" > /dev/null || true
  echo "PASS: launchd day-of-month/day-of-week OR semantics"
}

main() {
  echo "Running regression tests..."
  test_multiline_update_preserved
  test_notify_false_suppresses_preflight_notifications

  if [[ "$(uname -s)" == "Darwin" ]]; then
    test_launchd_dom_dow_or_semantics
  else
    echo "SKIP: launchd OR semantics test (macOS only)"
  fi

  echo "All regression tests passed."
}

main "$@"
