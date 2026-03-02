---
name: schedule
description: Create, manage, and run scheduled Claude Code tasks. Use when the user wants to schedule automated tasks, set up recurring jobs, list or remove scheduled tasks, pause/resume schedules, run a task immediately, or view task logs. Recognizes time expressions like "every weekday at 9am", "daily", "every hour", cron expressions, and similar scheduling language.
user-invocable: true
allowed-tools: Bash, Read
---

# Claude Code Scheduler

You help users create and manage scheduled Claude Code tasks that run automatically via the operating system's native scheduler (launchd on macOS, crontab on Linux).

## Scripts

All scripts are located at `${CLAUDE_PLUGIN_ROOT}/scripts/`. Always use the full path with `${CLAUDE_PLUGIN_ROOT}` when calling them.

### task-manager.sh — Task CRUD

```bash
# Create a new task
${CLAUDE_PLUGIN_ROOT}/scripts/task-manager.sh create \
  --name "Task name" \
  --schedule "0 9 * * 1-5" \
  --schedule-human "Every weekday at 9am" \
  --working-dir "/path/to/project" \
  --prompt "What Claude should do" \
  --allowed-tools "Read,Grep,Glob" \
  --max-turns 10 \
  --notify true

# List all tasks
${CLAUDE_PLUGIN_ROOT}/scripts/task-manager.sh list --format table

# Get task details
${CLAUDE_PLUGIN_ROOT}/scripts/task-manager.sh get <task-id>

# Update a task
${CLAUDE_PLUGIN_ROOT}/scripts/task-manager.sh update <task-id> --status paused

# Delete a task (also removes logs)
${CLAUDE_PLUGIN_ROOT}/scripts/task-manager.sh delete <task-id>
```

### platform-scheduler.sh — OS Scheduler Registration

```bash
# Register task with launchd/crontab
${CLAUDE_PLUGIN_ROOT}/scripts/platform-scheduler.sh register <task-id>

# Unregister (remove from scheduler)
${CLAUDE_PLUGIN_ROOT}/scripts/platform-scheduler.sh unregister <task-id>

# Force immediate execution (macOS: launchctl start; Linux: no-op, cron fires within 60s)
${CLAUDE_PLUGIN_ROOT}/scripts/platform-scheduler.sh start <task-id>

# Check registration status
${CLAUDE_PLUGIN_ROOT}/scripts/platform-scheduler.sh status <task-id>

# Check all tasks
${CLAUDE_PLUGIN_ROOT}/scripts/platform-scheduler.sh status-all
```

### run-task.sh — Execute a Task Immediately

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-task.sh <task-id>
```

Note: One-shot tasks (created with `--one-shot true`) automatically unregister from the scheduler and mark themselves as completed after execution.

## Operations

### Adding a scheduled task

When the user wants to schedule something:

1. Parse their request to determine: task name, schedule, working directory, prompt, and tool restrictions
2. Convert natural language time expressions to a 5-field cron expression (see [CRON_REFERENCE.md](CRON_REFERENCE.md))
3. Use the current working directory unless the user specifies otherwise
4. Call `task-manager.sh create` with all parameters
5. Call `platform-scheduler.sh register` with the returned task ID
6. Confirm to the user with the full schedule summary

For the `--prompt` argument, write a detailed, self-contained prompt. The task runs in a completely fresh Claude session with no conversation history, so the prompt must include everything Claude needs to know. Be specific about what to do and where to put the output.

Bad prompt: `"Send a greeting to the user"`
Good prompt: `"Write a friendly greeting for Bryan to stdout. Mention the current day of the week and wish him a productive day."`

Bad prompt: `"Review the code"`
Good prompt: `"In the repository at /Users/bryan/project, review all commits from the last 24 hours. Summarize what changed, flag anything that looks risky, and write the summary to stdout."`

For `--allowed-tools`, choose appropriate tools based on what the task needs:
- Read-only tasks: `"Read,Grep,Glob"`
- Tasks that run commands: `"Read,Grep,Glob,Bash"`
- Tasks that modify files: `"Read,Grep,Glob,Edit,Write,Bash"`

### Listing tasks

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task-manager.sh list --format table
```

Present the output to the user. If they want more detail on a specific task, use `get`.

### Removing a task

Always unregister from the OS scheduler first, then delete the task:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/platform-scheduler.sh unregister <task-id>
${CLAUDE_PLUGIN_ROOT}/scripts/task-manager.sh delete <task-id>
```

### Running a task immediately

**IMPORTANT: You CANNOT call `run-task.sh` from within this Claude session.** It invokes `claude -p` which starts a nested Claude process, and nested Claude sessions are not supported. The call will fail.

Instead, to run a task "now":
1. Create the task with `--one-shot true` and schedule `"* * * * *"`
2. Register it with `platform-scheduler.sh register`
3. Force immediate execution with `platform-scheduler.sh start`

The `start` command calls `launchctl start` on macOS to trigger the job immediately via launchd (not as a nested process). On Linux, cron will fire within 60 seconds.

The task automatically cleans up after itself: `run-task.sh` unregisters the task from the scheduler and marks it as completed after execution. A lock file prevents duplicate runs.

Tell the user the task is running now (macOS) or will run within 60 seconds (Linux). They'll get a desktop notification with the output when it completes.

```bash
# Create a one-shot task
${CLAUDE_PLUGIN_ROOT}/scripts/task-manager.sh create \
  --name "One-time task" \
  --schedule "* * * * *" \
  --one-shot true \
  --working-dir "$(pwd)" \
  --prompt "The task prompt"

# Register and start immediately
${CLAUDE_PLUGIN_ROOT}/scripts/platform-scheduler.sh register <task-id>
${CLAUDE_PLUGIN_ROOT}/scripts/platform-scheduler.sh start <task-id>
```

The user can check the result afterward with:
```bash
cat ~/.claude-scheduler/logs/<task-id>/latest
```

### Pausing a task

Unregister from scheduler and update status:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/platform-scheduler.sh unregister <task-id>
${CLAUDE_PLUGIN_ROOT}/scripts/task-manager.sh update <task-id> --status paused
```

### Resuming a task

Update status and re-register:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task-manager.sh update <task-id> --status active
${CLAUDE_PLUGIN_ROOT}/scripts/platform-scheduler.sh register <task-id>
```

### Viewing logs

```bash
cat ~/.claude-scheduler/logs/<task-id>/latest
```

Or list all log files:

```bash
ls -la ~/.claude-scheduler/logs/<task-id>/
```

## Important notes

- **Never call `run-task.sh` from this session.** It starts a nested `claude -p` process which will fail. Use the register-then-unregister pattern for immediate execution.
- Cron/launchd minimum granularity is 1 minute. You cannot schedule anything with sub-minute precision.
- Tasks run with the user's system permissions
- The `claude` CLI must be installed and in PATH for scheduled execution
- Desktop notifications are enabled by default
- Logs are stored at `~/.claude-scheduler/logs/<task-id>/`
- macOS uses launchd (persists across reboots, runs missed jobs after wake)
- Linux uses crontab (persists across reboots)
- Windows is not supported
- Tasks do NOT use `--dangerously-skip-permissions` — they run with the allowed tools specified
