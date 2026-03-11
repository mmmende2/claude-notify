#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.claude/claude-notify"
SETTINGS="$HOME/.claude/settings.json"
REPO_URL="https://github.com/mmmende2/claude-notify.git"

echo "claude-notify installer"
echo "======================"
echo ""

# --- Dependencies ---

if ! command -v brew &>/dev/null; then
  echo "error: Homebrew is required. Install from https://brew.sh" >&2
  exit 1
fi

missing=()
command -v alerter &>/dev/null || missing+=(vjeantet/tap/alerter)
command -v jq &>/dev/null || missing+=(jq)

if [ ${#missing[@]} -gt 0 ]; then
  echo "Installing dependencies: ${missing[*]}"
  brew install "${missing[@]}"
else
  echo "Dependencies: ok (alerter, jq)"
fi

# --- Clone / update ---

if [ -d "$INSTALL_DIR/.git" ]; then
  echo "Updating $INSTALL_DIR"
  git -C "$INSTALL_DIR" pull --ff-only --quiet
else
  if [ -d "$INSTALL_DIR" ]; then
    echo "Removing stale $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
  fi
  echo "Cloning to $INSTALL_DIR"
  git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/claude-notify.sh"

# --- Configure hooks in settings.json ---

HOOKS='{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash '"$INSTALL_DIR"'/claude-notify.sh check_deps",
            "timeout": 10
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "bash '"$INSTALL_DIR"'/claude-notify.sh idle_prompt",
            "timeout": 120
          }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "bash '"$INSTALL_DIR"'/claude-notify.sh permission_prompt",
            "timeout": 75
          }
        ]
      }
    ]
  }
}'

mkdir -p "$(dirname "$SETTINGS")"

if [ -f "$SETTINGS" ]; then
  existing=$(cat "$SETTINGS")
else
  existing='{}'
fi

# Check if hooks already configured for claude-notify
if echo "$existing" | jq -e '.hooks.SessionStart[0].hooks[0].command // ""' 2>/dev/null | grep -q 'claude-notify'; then
  echo "Hooks: already configured"
else
  # Merge hooks into existing settings (overwrites any existing hooks key)
  echo "$existing" | jq --argjson hooks "$(echo "$HOOKS" | jq '.hooks')" '.hooks = $hooks' > "$SETTINGS.tmp"
  mv "$SETTINGS.tmp" "$SETTINGS"
  echo "Hooks: added to $SETTINGS"
fi

echo ""
echo "Installed! Restart Claude Code for hooks to take effect."
echo ""
echo "Test with:"
echo "  bash $INSTALL_DIR/claude-notify.sh test_notify"
