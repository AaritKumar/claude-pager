#!/usr/bin/env bash
set -euo pipefail

case "$(uname)" in
  Darwin|Linux) ;;
  *)
    echo "Error: claude-pager supports macOS and Linux. On Windows, run this from WSL or Git Bash." >&2
    exit 1
    ;;
esac

for dep in curl python3; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "Error: '$dep' is required but not found on PATH." >&2
    exit 1
  fi
done

read -r -s -p "Paste your Bark device key: " DEVICE_KEY
echo
if [ -z "$DEVICE_KEY" ]; then
  echo "Error: device key cannot be empty." >&2
  exit 1
fi

# Bark shows the key as a full URL (https://api.day.app/YOUR_DEVICE_KEY/) —
# accept that form too by stripping the host prefix and any trailing slash.
DEVICE_KEY="${DEVICE_KEY#https://api.day.app/}"
DEVICE_KEY="${DEVICE_KEY%/}"

if [[ ! "$DEVICE_KEY" =~ ^[A-Za-z0-9]+$ ]]; then
  echo "Error: device key must contain only letters and numbers." >&2
  exit 1
fi

if [ "${CLAUDE_PAGER_SKIP_CURL:-0}" != "1" ]; then
  if ! curl -fsS --connect-timeout 5 --max-time 10 \
      "https://api.day.app/${DEVICE_KEY}/Claude%20Pager/Installed%20successfully?sound=minuet" \
      >/dev/null; then
    echo "Error: test notification failed. Double-check your device key and network connection." >&2
    exit 1
  fi
  echo "Test notification sent — check your phone."
fi

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
mkdir -p "$CLAUDE_DIR"

BACKUP_FILE=""
if [ -f "$SETTINGS_FILE" ]; then
  BACKUP_FILE="${SETTINGS_FILE}.bak.$(date +%s).$$"
  cp "$SETTINGS_FILE" "$BACKUP_FILE"
  echo "Backed up existing settings to $BACKUP_FILE"
fi

if ! python3 - "$SETTINGS_FILE" "$DEVICE_KEY" <<'PYEOF'
import json
import sys

settings_path, device_key = sys.argv[1], sys.argv[2]

try:
    with open(settings_path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except json.JSONDecodeError:
    sys.exit(1)

hooks = data.setdefault("hooks", {})

def make_hook(title, body, sound):
    url = f"https://api.day.app/{device_key}/{title}/{body}?sound={sound}&group=claude-pager"
    command = (
        f"curl -s --connect-timeout 2 --max-time 5 '{url}' >/dev/null 2>&1"
    )
    return {
        "matcher": "",
        "hooks": [{"type": "command", "command": command, "async": True}],
    }

EVENTS = {
    "Notification": make_hook(
        "Claude%20Needs%20You", "Claude%20Code%20is%20waiting%20for%20your%20input", "minuet"
    ),
    "Stop": make_hook(
        "Claude%20Finished", "Claude%20Code%20finished%20its%20response", "glass"
    ),
    "StopFailure": make_hook(
        "Claude%20Stopped", "Claude%20Code%20encountered%20an%20error", "alarm"
    ),
}

def is_bark_hook(command):
    # Detect both our own tagged hooks (group=claude-pager) and legacy
    # hand-written Bark hooks from the old manual setup (no group= param,
    # just a bare api.day.app URL) — both get replaced on install.
    return "group=claude-pager" in command or "api.day.app" in command

for event, hook_entry in EVENTS.items():
    entries = hooks.setdefault(event, [])
    kept = [
        entry for entry in entries
        if not any(is_bark_hook(h.get("command", "")) for h in entry.get("hooks", []))
    ]
    kept.append(hook_entry)
    hooks[event] = kept

with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
then
  echo "Error: $SETTINGS_FILE is not valid JSON. Fix it (python3 -m json.tool ~/.claude/settings.json) and re-run." >&2
  exit 1
fi

if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SETTINGS_FILE" >/dev/null 2>&1; then
  echo "Error: wrote invalid JSON to $SETTINGS_FILE." >&2
  if [ -n "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SETTINGS_FILE"
    echo "Restored previous settings from backup." >&2
  fi
  exit 1
fi

echo "claude-pager hooks installed in $SETTINGS_FILE"
echo "Restart Claude Code (/exit then claude) and run /hooks to confirm."
