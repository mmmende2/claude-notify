#!/usr/bin/env bash
set -euo pipefail

# Ensure Homebrew is on PATH
export PATH="/opt/homebrew/bin:$PATH"

# Temp dir for session state
STATE_DIR="/tmp/claude-notify"
mkdir -p "$STATE_DIR"

# Read all stdin upfront (before case dispatch) to avoid hanging on cat
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

# Extract context from pre-read stdin JSON
read_context() {
  session_id=$(echo "$STDIN_DATA" | jq -r '.session_id // ""' 2>/dev/null || echo "")
  transcript_path=$(echo "$STDIN_DATA" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
  cwd=$(echo "$STDIN_DATA" | jq -r '.cwd // ""' 2>/dev/null || echo "")
  message=$(echo "$STDIN_DATA" | jq -r '.message // ""' 2>/dev/null || echo "")
  if [ -n "$cwd" ]; then
    dir_name=$(basename "$cwd")
    git_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  else
    dir_name=$(basename "$PWD")
    git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  fi
  subtitle="${dir_name}${git_branch:+ | $git_branch}"
}

# Get Claude's last text message from the transcript
get_last_claude_message() {
  local max_chars="${1:-200}"
  if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
    return
  fi
  # Find last assistant entry with text content, extract and truncate
  grep -a '"type":"assistant"' "$transcript_path" 2>/dev/null \
    | jq -r 'select(.message.content | map(select(.type == "text")) | length > 0) | .message.content[] | select(.type == "text") | .text' 2>/dev/null \
    | tail -1 \
    | head -c "$max_chars"
}

# Inject text into the iTerm2 session that Claude Code is running in
# Runs in background with a delay so the hook script exits first
# and Claude Code regains the foreground of the TTY
inject_text() {
  local text="$1"
  local tty_path="${2:-}"

  if [ -z "$tty_path" ] || [ ! -e "$tty_path" ]; then
    echo -n "$text" | pbcopy
    return 0
  fi

  # Fork to background — inject after hook exits
  (
    sleep 1
    # Focus the session first, then write text
    focus_session "$tty_path"
    sleep 0.3
    osascript <<EOF 2>/dev/null || { echo -n "$text" | pbcopy; }
tell application "iTerm"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if tty of s is "$tty_path" then
          tell s to write text "$text"
          return
        end if
      end repeat
    end repeat
  end repeat
end tell
EOF
  ) &
  disown
}

# Focus the iTerm2 window/tab/pane containing the Claude Code session
focus_session() {
  local tty_path="${1:-}"

  if [ -z "$tty_path" ]; then
    osascript -e 'tell application "iTerm" to activate' 2>/dev/null || true
    return
  fi

  osascript <<EOF 2>/dev/null || { osascript -e 'tell application "iTerm" to activate' 2>/dev/null || true; }
tell application "iTerm"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if tty of s is "$tty_path" then
          select w
          select t
          select s
          activate
          return
        end if
      end repeat
    end repeat
  end repeat
  -- Fallback: just activate
  activate
end tell
EOF
}

# --- Commands ---

MODE="${1:-help}"

case "$MODE" in

  check_deps)
    for cmd in alerter jq; do
      if ! command -v "$cmd" &>/dev/null; then
        echo "claude-notify: missing dependency '$cmd'. Run: brew install vjeantet/tap/alerter jq" >&2
      fi
    done

    # Store the TTY of Claude Code's process for later session targeting
    read_context
    parent_tty=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')
    if [ -n "$parent_tty" ] && [ -n "$session_id" ]; then
      echo "/dev/$parent_tty" > "$STATE_DIR/$session_id.tty"
    fi

    echo "claude-notify: ready" >&2
    ;;

  idle_prompt)
    read_context
    last_msg=$(get_last_claude_message 200)

    # Show notification with reply field
    reply=$(alerter \
      --title "Claude is waiting" \
      --subtitle "$subtitle" \
      --message "${last_msg:-Reply below or return to terminal}" \
      --sound "Ping" \
      --reply "Enter your response..." \
      2>/dev/null || true)

    # Focus iTerm2 and select the Claude Code session when clicked
    if [ "$reply" = "@CONTENTCLICKED" ] || [ "$reply" = "@ACTIONCLICKED" ]; then
      tty_path=""
      [ -n "$session_id" ] && [ -f "$STATE_DIR/$session_id.tty" ] && tty_path=$(cat "$STATE_DIR/$session_id.tty")
      focus_session "$tty_path"
      exit 0
    fi

    # Ignore other special return values
    case "$reply" in
      @TIMEOUT|@CLOSED|"") exit 0 ;;
    esac

    # Inject reply into Claude Code's iTerm2 session
    tty_path=""
    [ -n "$session_id" ] && [ -f "$STATE_DIR/$session_id.tty" ] && tty_path=$(cat "$STATE_DIR/$session_id.tty")
    inject_text "$reply" "$tty_path"
    ;;

  permission_prompt)
    read_context
    # Strip redundant prefix — "Claude needs your permission to use Bash" → "to use Bash"
    tool_info=$(echo "$message" | sed 's/^Claude needs your permission //' 2>/dev/null || echo "$message")

    result=$(alerter \
      --title "Claude needs permission" \
      --subtitle "$subtitle" \
      --message "${tool_info:-to use a tool}" \
      --sound "Basso" \
      2>/dev/null || true)

    # Focus iTerm2 and select the Claude Code session when clicked
    if [ "$result" = "@CONTENTCLICKED" ] || [ "$result" = "@ACTIONCLICKED" ]; then
      tty_path=""
      [ -n "$session_id" ] && [ -f "$STATE_DIR/$session_id.tty" ] && tty_path=$(cat "$STATE_DIR/$session_id.tty")
      focus_session "$tty_path"
    fi
    ;;

  # --- Manual test commands ---
  # All test commands auto-detect the most recent session TTY for focus/inject.

  test_idle)
    latest_session=$(ls -t "$STATE_DIR"/*.tty 2>/dev/null | head -1 | xargs -I{} basename {} .tty)
    echo '{"cwd":"'"$PWD"'","message":"Claude is waiting for your input","session_id":"'"${latest_session:-test}"'"}' | "$0" idle_prompt
    ;;

  test_permission)
    latest_session=$(ls -t "$STATE_DIR"/*.tty 2>/dev/null | head -1 | xargs -I{} basename {} .tty)
    echo '{"cwd":"'"$PWD"'","message":"Claude needs your permission to use Bash","session_id":"'"${latest_session:-test}"'"}' | "$0" permission_prompt
    ;;

  test_notify)
    latest_tty=""
    latest_file=$(ls -t "$STATE_DIR"/*.tty 2>/dev/null | head -1)
    [ -n "$latest_file" ] && latest_tty=$(cat "$latest_file")

    result=$(alerter \
      --title "claude-notify test" \
      --subtitle "$(basename "$PWD")" \
      --message "Click to focus Claude Code session" \
      --sound "Ping" \
      --timeout 10 2>/dev/null || true)

    if [ "$result" = "@CONTENTCLICKED" ] || [ "$result" = "@ACTIONCLICKED" ]; then
      focus_session "$latest_tty"
    fi
    ;;

  help|*)
    cat <<'USAGE'
claude-notify.sh — macOS notifications for Claude Code

Hook modes (called by Claude Code):
  check_deps          Check for alerter and jq, store session TTY
  idle_prompt         Show reply notification when Claude is idle
  permission_prompt   Show alert when Claude needs permission

Manual test modes:
  test_idle           Simulate an idle_prompt notification
  test_permission     Simulate a permission_prompt notification
  test_notify         Send a basic test notification

Examples:
  bash claude-notify.sh test_notify
  bash claude-notify.sh test_idle
  bash claude-notify.sh test_permission
USAGE
    ;;

esac
