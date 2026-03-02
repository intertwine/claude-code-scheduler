#!/usr/bin/env bash
set -euo pipefail

# Cross-platform desktop notifications for Claude Scheduler

title=""
subtitle=""
message=""
sound=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)    title="$2";    shift 2 ;;
    --subtitle) subtitle="$2"; shift 2 ;;
    --message)  message="$2";  shift 2 ;;
    --success)  sound="default"; shift ;;
    --failure)  sound="Basso";   shift ;;
    *) shift ;;
  esac
done

[[ -z "$title" ]] && title="Claude Scheduler"
[[ -z "$message" ]] && { echo "Usage: notify.sh --title TITLE --message MSG [--subtitle SUB] [--success|--failure]" >&2; exit 1; }

# Escape for AppleScript string literals
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

case "$(uname -s)" in
  Darwin)
    sound_clause=""
    subtitle_clause=""
    [[ -n "$sound" ]] && sound_clause=" sound name \"$(esc "$sound")\""
    [[ -n "$subtitle" ]] && subtitle_clause=" subtitle \"$(esc "$subtitle")\""
    osascript -e "display notification \"$(esc "$message")\" with title \"$(esc "$title")\"${subtitle_clause}${sound_clause}" 2>/dev/null || true
    ;;
  Linux)
    if command -v notify-send &>/dev/null; then
      body="$message"
      [[ -n "$subtitle" ]] && body="${subtitle}: ${message}"
      notify-send "$title" "$body" 2>/dev/null || true
    fi
    ;;
esac

# Always log to stderr as fallback
echo "[notify] ${title}: ${message}" >&2
