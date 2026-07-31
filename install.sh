#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname)" != "Darwin" ]; then
  echo "Error: claude-pager only supports macOS." >&2
  exit 1
fi

for dep in curl python3; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "Error: '$dep' is required but not found on PATH." >&2
    exit 1
  fi
done

read -r -p "Paste your Bark device key: " DEVICE_KEY
if [ -z "$DEVICE_KEY" ]; then
  echo "Error: device key cannot be empty." >&2
  exit 1
fi
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
  BACKUP_FILE="${SETTINGS_FILE}.bak.$(date +%s)"
  cp "$SETTINGS_FILE" "$BACKUP_FILE"
  echo "Backed up existing settings to $BACKUP_FILE"
fi

python3 - "$SETTINGS_FILE" "$DEVICE_KEY" <<'PYEOF'
import json
import sys

settings_path, device_key = sys.argv[1], sys.argv[2]

try:
    with open(settings_path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}

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

for event, hook_entry in EVENTS.items():
    entries = hooks.setdefault(event, [])
    already_installed = any(
        "group=claude-pager" in h.get("command", "")
        for entry in entries
        for h in entry.get("hooks", [])
    )
    if not already_installed:
        entries.append(hook_entry)

with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

if ! python3 -c "import json; json.load(open('$SETTINGS_FILE'))" >/dev/null 2>&1; then
  echo "Error: wrote invalid JSON to $SETTINGS_FILE." >&2
  if [ -n "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SETTINGS_FILE"
    echo "Restored previous settings from backup." >&2
  fi
  exit 1
fi

echo "claude-pager hooks installed in $SETTINGS_FILE"
echo "Restart Claude Code (/exit then claude) and run /hooks to confirm."
