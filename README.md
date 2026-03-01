# Claude Code Scheduler

Schedule Claude Code tasks to run automatically. Zero dependencies beyond shell and Python 3.

Inspired by [this tweet](https://x.com/daviddiviny/status/2028210513038180550) — Claude Cowork has scheduled tasks but limited CLI access, Claude Code has full CLI power but no scheduling. This plugin bridges the gap.

## Install

```
/plugin install bryanyoung/claude-code-scheduler
```

## Uninstall

```
/plugin uninstall scheduler
rm -rf ~/.claude-scheduler  # optional: remove task data and logs
```

## Usage

Talk to Claude naturally:

```
You: /schedule Review my code for security issues every weekday at 9am
You: /schedule List my scheduled tasks
You: /schedule Run the security review task now
You: /schedule Pause the security review
You: /schedule Remove the security review task
You: /schedule Show me the logs for the security review
```

Or be specific with cron:

```
You: /schedule Add a task with cron "*/30 9-17 * * 1-5" to check for TODO comments in this project
```

## How It Works

```
/schedule ─> SKILL.md ─> task-manager.sh ─> ~/.claude-scheduler/tasks/<id>.json
                         platform-scheduler.sh ─> launchd plist or crontab entry
                                                       │
                                                       ▼ (at scheduled time)
                                                  run-task.sh
                                                       │
                                                       ▼
                                              claude -p "<prompt>"
                                                       │
                                                       ▼
                                              log output + notify
```

1. You describe what you want scheduled and when
2. Claude creates a task definition and registers it with your OS scheduler
3. At the scheduled time, launchd (macOS) or cron (Linux) runs the task
4. The task invokes `claude -p` with your prompt and tool configuration
5. Output is logged and you get a desktop notification

## Requirements

- Claude Code v1.0.33+
- macOS or Linux (Windows not supported)
- Python 3 (ships with macOS and most Linux distributions)
- `claude` CLI in your PATH

## File Structure

```
claude-code-scheduler/
├── .claude-plugin/plugin.json       # Plugin metadata
├── skills/schedule/
│   ├── SKILL.md                     # Skill instructions
│   └── CRON_REFERENCE.md            # Cron syntax reference
└── scripts/
    ├── task-manager.sh              # Task CRUD operations
    ├── platform-scheduler.sh        # launchd/crontab management
    ├── run-task.sh                  # Execution wrapper
    └── notify.sh                    # Desktop notifications
```

## Data Storage

All data lives in `~/.claude-scheduler/`:

```
~/.claude-scheduler/
├── tasks/          # Task definition JSON files
│   └── a1b2c3d4.json
└── logs/           # Per-task execution logs
    └── a1b2c3d4/
        ├── 20260301_090000.log
        └── latest -> 20260301_090000.log
```

## Task Configuration

| Field | Default | Description |
|-------|---------|-------------|
| `name` | (required) | Human-readable task name |
| `schedule` | (required) | 5-field cron expression |
| `prompt` | (required) | What Claude should do |
| `working_directory` | Current dir | Where the task runs |
| `allowed_tools` | `Read,Grep,Glob` | Tools available during execution |
| `max_turns` | `10` | Maximum agentic turns per run |
| `notify` | `true` | Desktop notification on completion |

## Troubleshooting

**Task not running?**

```bash
# Check if the task is registered with the scheduler
# macOS:
launchctl list | grep claude-scheduler

# Linux:
crontab -l | grep claude-scheduler
```

**Check task logs:**

```bash
cat ~/.claude-scheduler/logs/<task-id>/latest
```

**Claude CLI not found during scheduled execution?**

The run script sets a broad PATH, but if `claude` is installed somewhere unusual, check:

```bash
which claude
```

And ensure that path is included in the script's PATH or in your shell profile.

**macOS: launchd not running task after sleep?**

launchd runs missed jobs after the machine wakes up. If it's still not working, verify the plist is loaded:

```bash
launchctl list | grep claude-scheduler
```

## How It Compares

| | This plugin | jshchnz/claude-code-scheduler | kylemclaren/claude-tasks |
|---|---|---|---|
| Dependencies | Shell + Python 3 | Node.js + TypeScript | Go |
| Files | 9 | 30+ | 20+ |
| Install | One command | One command | Binary download |
| Windows | No | Yes | Yes |
| Approach | Shell scripts | TypeScript | Go TUI |

Our goal is radical simplicity: 9 files, zero external dependencies, easy to read and modify.

## License

MIT
