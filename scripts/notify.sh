#!/usr/bin/env bash
set -euo pipefail

# Cross-platform desktop notifications for Claude Scheduler

title=""
message=""
sound=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)    title="$2";   shift 2 ;;
    --message)  message="$2"; shift 2 ;;
    --success)  sound="default"; shift ;;
    --failure)  sound="Basso";   shift ;;
    *) shift ;;
  esac
done

[[ -z "$title" ]] && title="Claude Scheduler"
[[ -z "$message" ]] && { echo "Usage: notify.sh --title TITLE --message MSG [--success|--failure]" >&2; exit 1; }

case "$(uname -s)" in
  Darwin)
    sound_clause=""
    [[ -n "$sound" ]] && sound_clause=" sound name \"${sound}\""
    osascript -e "display notification \"${message}\" with title \"${title}\"${sound_clause}" 2>/dev/null || true
    ;;
  Linux)
    if command -v notify-send &>/dev/null; then
      notify-send "$title" "$message" 2>/dev/null || true
    fi
    ;;
esac

# Always log to stderr as fallback
echo "[notify] ${title}: ${message}" >&2
