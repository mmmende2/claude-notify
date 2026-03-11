# claude-notify

macOS notifications for [Claude Code](https://claude.ai/code) via [alerter](https://github.com/vjeantet/alerter). Get notified when Claude is idle or needs permission — reply directly from the notification.

## Features

- **Idle notifications** with reply field — type your response without switching apps
- **Permission notifications** — see what tool Claude wants to use (e.g., "to use Bash")
- **Click to focus** — clicking a notification focuses the exact iTerm2 tab/pane running Claude
- **Context-rich** — shows project directory, git branch, and Claude's last message
- **Reply injection** — replies are sent directly to your Claude Code session via iTerm2 AppleScript

## Requirements

- macOS
- [iTerm2](https://iterm2.com/)
- [alerter](https://github.com/vjeantet/alerter) and [jq](https://jqlang.github.io/jq/)

## Install

```bash
# Install dependencies
brew install vjeantet/tap/alerter jq

# Install the plugin (from within Claude Code)
/plugin install gh:mario/claude-notify

# Or manually
git clone https://github.com/mario/claude-notify ~/.claude/plugins/manual/claude-notify

# Restart Claude Code for hooks to take effect
```

## macOS Notification Settings

By default, macOS shows notifications as **banners** that auto-dismiss after a few seconds. To make claude-notify notifications persist until you interact with them:

1. Open **System Settings > Notifications**
2. Find **Terminal** in the app list
3. Change **Alert Style** from "Banners" to **"Alerts"**

## How It Works

claude-notify uses Claude Code's [hooks system](https://docs.anthropic.com/en/docs/claude-code/hooks) to listen for two notification events:

| Event | Trigger | Notification |
|-------|---------|-------------|
| `idle_prompt` | Claude idle for 60s | Shows Claude's last message + reply field |
| `permission_prompt` | Claude needs tool permission | Shows which tool (e.g., "to use Bash") |

On session start, the plugin stores the TTY of your Claude Code process. When you interact with a notification, it uses this TTY to find and focus the correct iTerm2 session — even across multiple windows and tabs.

Replies typed in idle notifications are injected into your Claude Code session via iTerm2's native AppleScript API (`write text`).

## Test Commands

Run these from any terminal to verify the plugin works:

```bash
# Basic notification — click to focus Claude Code pane
bash ~/.claude/plugins/manual/claude-notify/claude-notify.sh test_notify

# Permission prompt
bash ~/.claude/plugins/manual/claude-notify/claude-notify.sh test_permission

# Idle prompt with reply field
bash ~/.claude/plugins/manual/claude-notify/claude-notify.sh test_idle
```

## Limitations

- **iTerm2 only** — reply injection uses iTerm2's AppleScript API. Other terminals are not currently supported.
- **Notification timing** — `idle_prompt` and `permission_prompt` notifications fire after ~60 seconds of no user response, not immediately.
- **Reply injection timing** — replies are injected with a ~1 second delay after the notification is dismissed. This is necessary so the hook script exits and Claude Code regains the TTY foreground.

## License

MIT
