#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "--- case: removes only claude-pager entries ---"
tmp_home="$(mktemp -d)"
mkdir -p "$tmp_home/.claude"
cat > "$tmp_home/.claude/settings.json" <<JSON
{
  "model": "claude-sonnet-5",
  "hooks": {
    "Stop": [
      {"matcher": "", "hooks": [{"type": "command", "command": "echo unrelated"}]},
      {"matcher": "", "hooks": [{"type": "command", "command": "curl 'https://api.day.app/KEY/Claude%20Finished/x?sound=glass&group=claude-pager'", "async": true}]}
    ],
    "Notification": [
      {"matcher": "", "hooks": [{"type": "command", "command": "curl 'https://api.day.app/KEY/Claude%20Needs%20You/x?sound=minuet&group=claude-pager'", "async": true}]}
    ]
  }
}
JSON
status=0
if HOME="$tmp_home" "$SCRIPT_DIR/uninstall.sh" >/tmp/uninstall_out.txt 2>&1; then
  status=0
else
  status=$?
fi
if [ "$status" -ne 0 ]; then
  echo "FAIL: uninstall.sh exited $status"
  cat /tmp/uninstall_out.txt
  exit 1
fi
python3 - "$tmp_home/.claude/settings.json" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["model"] == "claude-sonnet-5", "unrelated top-level key lost"
stop_hooks = data["hooks"]["Stop"]
assert len(stop_hooks) == 1, f"expected 1 remaining Stop hook, found {len(stop_hooks)}"
assert "echo unrelated" in stop_hooks[0]["hooks"][0]["command"], "unrelated Stop hook removed incorrectly"
assert "Notification" not in data.get("hooks", {}), "Notification key should be dropped once empty"
print("OK: only claude-pager entries removed")
EOF
rm -rf "$tmp_home"

echo "--- case: no settings.json is a no-op ---"
tmp_home="$(mktemp -d)"
status=0
if HOME="$tmp_home" "$SCRIPT_DIR/uninstall.sh" >/tmp/uninstall_out2.txt 2>&1; then
  status=0
else
  status=$?
fi
if [ "$status" -ne 0 ]; then
  echo "FAIL: uninstall.sh exited $status on no settings.json"
  cat /tmp/uninstall_out2.txt
  exit 1
fi
grep -q "nothing to uninstall" /tmp/uninstall_out2.txt
rm -rf "$tmp_home"

echo "All uninstall.sh cases passed"
