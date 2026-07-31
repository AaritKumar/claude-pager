#!/usr/bin/env bash
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: 'python3' is required but not found on PATH." >&2
  exit 1
fi

SETTINGS_FILE="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
  echo "No settings file found at $SETTINGS_FILE — nothing to uninstall."
  exit 0
fi

BACKUP_FILE="${SETTINGS_FILE}.bak.$(date +%s).$$"
cp "$SETTINGS_FILE" "$BACKUP_FILE"
echo "Backed up existing settings to $BACKUP_FILE"

if ! python3 - "$SETTINGS_FILE" <<'PYEOF'
import json
import sys

settings_path = sys.argv[1]

try:
    with open(settings_path) as f:
        data = json.load(f)
except json.JSONDecodeError:
    sys.exit(1)

hooks = data.get("hooks")
if hooks:
    for event in ("Notification", "Stop", "StopFailure"):
        entries = hooks.get(event)
        if not entries:
            continue
        kept = [
            entry for entry in entries
            if not any("group=claude-pager" in h.get("command", "") for h in entry.get("hooks", []))
        ]
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    if not hooks:
        del data["hooks"]

with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
then
  echo "Error: $SETTINGS_FILE is not valid JSON. Fix it (python3 -m json.tool ~/.claude/settings.json) and re-run." >&2
  cp "$BACKUP_FILE" "$SETTINGS_FILE"
  exit 1
fi

if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SETTINGS_FILE" >/dev/null 2>&1; then
  echo "Error: wrote invalid JSON to $SETTINGS_FILE." >&2
  cp "$BACKUP_FILE" "$SETTINGS_FILE"
  echo "Restored previous settings from backup." >&2
  exit 1
fi

echo "claude-pager hooks removed from $SETTINGS_FILE"
