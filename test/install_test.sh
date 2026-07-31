#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0

run_case() {
  local name="$1"
  local setup="$2"
  echo "--- case: $name ---"
  local tmp_home
  tmp_home="$(mktemp -d)"
  eval "$setup"
  echo "fake-device-key" | HOME="$tmp_home" CLAUDE_PAGER_SKIP_CURL=1 "$SCRIPT_DIR/install.sh" >/tmp/install_out.txt 2>&1
  local status=$?
  if [ $status -ne 0 ]; then
    echo "FAIL: install.sh exited $status"
    cat /tmp/install_out.txt
    FAILS=$((FAILS+1))
    rm -rf "$tmp_home"
    return
  fi
  python3 - "$tmp_home/.claude/settings.json" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
hooks = data.get("hooks", {})
for event in ("Notification", "Stop", "StopFailure"):
    entries = hooks.get(event, [])
    found = any("group=claude-pager" in h["command"]
                for entry in entries for h in entry.get("hooks", []))
    assert found, f"missing claude-pager hook for {event}"
print("OK: hooks present for", sys.argv[1])
EOF
  rm -rf "$tmp_home"
}

run_case "fresh install, no existing settings.json" "mkdir -p \$tmp_home"

run_case "preserves unrelated existing settings" '
mkdir -p "$tmp_home/.claude"
cat > "$tmp_home/.claude/settings.json" <<JSON
{"model": "claude-sonnet-5", "hooks": {"Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "echo unrelated"}]}]}}
JSON
'

echo "--- case: preserves unrelated settings.json content ---"
tmp_home="$(mktemp -d)"
mkdir -p "$tmp_home/.claude"
cat > "$tmp_home/.claude/settings.json" <<JSON
{"model": "claude-sonnet-5", "hooks": {"Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "echo unrelated"}]}]}}
JSON
echo "fake-device-key" | HOME="$tmp_home" CLAUDE_PAGER_SKIP_CURL=1 "$SCRIPT_DIR/install.sh" >/tmp/install_out.txt 2>&1
python3 - "$tmp_home/.claude/settings.json" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["model"] == "claude-sonnet-5", "unrelated top-level key lost"
stop_hooks = data["hooks"]["Stop"]
assert any("echo unrelated" in h["command"] for entry in stop_hooks for h in entry["hooks"]), "unrelated Stop hook lost"
assert any("group=claude-pager" in h["command"] for entry in stop_hooks for h in entry["hooks"]), "claude-pager Stop hook missing"
print("OK: unrelated settings preserved")
EOF
rm -rf "$tmp_home"

echo "--- case: idempotent re-run does not duplicate ---"
tmp_home="$(mktemp -d)"
echo "fake-device-key" | HOME="$tmp_home" CLAUDE_PAGER_SKIP_CURL=1 "$SCRIPT_DIR/install.sh" >/tmp/install_out.txt 2>&1
echo "fake-device-key" | HOME="$tmp_home" CLAUDE_PAGER_SKIP_CURL=1 "$SCRIPT_DIR/install.sh" >/tmp/install_out.txt 2>&1
python3 - "$tmp_home/.claude/settings.json" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
count = sum(1 for entry in data["hooks"]["Notification"] for h in entry["hooks"] if "group=claude-pager" in h["command"])
assert count == 1, f"expected exactly 1 claude-pager Notification hook, found {count}"
print("OK: idempotent re-run")
EOF
rm -rf "$tmp_home"

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS case(s) failed"
  exit 1
fi
echo "All install.sh cases passed"
