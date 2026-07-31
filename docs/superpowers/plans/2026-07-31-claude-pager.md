# claude-pager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an open-source MIT-licensed macOS utility (`claude-pager`) that installs Bark push-notification hooks into `~/.claude/settings.json` via a one-command installer, with a matching uninstaller.

**Architecture:** Two standalone bash scripts (`install.sh`, `uninstall.sh`) that never hand-edit JSON with `sed`; all reads/writes of `settings.json` go through an embedded `python3 -c` snippet so existing user settings are preserved. Both scripts are tested by running them with `HOME` redirected to a scratch directory and asserting on the resulting JSON with `python3 -c`.

**Tech Stack:** bash, python3 (stdlib `json` only), curl. No external dependencies, no package manager.

## Global Constraints

- macOS only; scripts must check `uname` reports `Darwin` and exit non-zero with a clear message otherwise.
- No dependency beyond `curl` and `python3` (already required by the original handoff doc's own JSON-validation step).
- Bark device key is entered interactively (`read -p`) — never hardcoded, never written to any file in this repo.
- All hook entries this repo manages use Bark notification `group=claude-pager` (not `claude-code`) so install/uninstall can find and touch only their own entries.
- Every settings.json write is preceded by a timestamped backup (`settings.json.bak.<unix-timestamp>`) of the prior file if one existed.
- Every settings.json write is followed by a `json.load` validation of the file just written; on failure, restore the backup and exit non-zero.
- License: MIT, copyright "AaritKumar", year 2026.
- Repo: `https://github.com/AaritKumar/claude-pager`, default branch `main` (already set up).

---

### Task 1: Repo scaffolding — LICENSE and README skeleton

**Files:**
- Create: `LICENSE`
- Create: `README.md`

**Interfaces:**
- Produces: the public-facing description of `install.sh` / `uninstall.sh` usage that Task 2 and Task 3 must match exactly (command names, flags, one-liner install command).

- [ ] **Step 1: Write LICENSE**

Create `LICENSE` with the standard MIT license text, copyright line `Copyright (c) 2026 AaritKumar`.

```text
MIT License

Copyright (c) 2026 AaritKumar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Write README.md**

```markdown
# claude-pager

Get an iPhone push notification the moment [Claude Code](https://claude.com/claude-code) needs your input, finishes a response, or hits an error — powered by [Bark](https://apps.apple.com/app/bark-customed-notifications/id1403753865).

| Claude Code event | Notification |
|---|---|
| Needs your attention/input | **Claude Needs You** (sound: minuet) |
| Finishes responding | **Claude Finished** (sound: glass) |
| Stops on an error | **Claude Stopped** (sound: alarm) |

All three are grouped under `claude-pager` on your phone.

## Requirements

- macOS
- [Claude Code](https://claude.com/claude-code) installed
- `curl` and `python3` (both ship with macOS)
- An iPhone with [Bark – Custom Notifications](https://apps.apple.com/app/bark-customed-notifications/id1403753865) installed, with notifications allowed

## Install

```bash
git clone https://github.com/AaritKumar/claude-pager.git
cd claude-pager
./install.sh
```

Open Bark on your iPhone, copy the device key it shows you (looks like `https://api.day.app/YOUR_DEVICE_KEY/`), and paste just the key when `install.sh` asks for it.

The script sends a real "Installed successfully" test notification before touching any files, then merges the three hooks into `~/.claude/settings.json` — any settings you already have there are preserved (and backed up first).

Restart Claude Code (`/exit` then `claude`) and run `/hooks` to confirm the three hooks loaded.

## Uninstall

```bash
./uninstall.sh
```

Removes only the `claude-pager` hook entries from `~/.claude/settings.json`; everything else you've configured is left untouched.

## How it works

Claude Code supports [hooks](https://docs.claude.com/en/docs/claude-code/hooks) — shell commands it runs on lifecycle events like `Notification`, `Stop`, and `StopFailure`. `claude-pager` wires each of those events to a `curl` call against your personal Bark URL, so your phone gets a push notification instead of you having to keep glancing at the terminal.

## Troubleshooting

**No notification on a manual test:**

```bash
curl "https://api.day.app/YOUR_DEVICE_KEY/Sound%20Test?sound=minuet"
```

If this doesn't produce a notification, the issue is on the Bark/iPhone side, not this tool. Check:
- Settings → Notifications → Bark → Allow Notifications + Sounds enabled
- Bark isn't inside your current Focus mode's blocked apps
- Bark isn't included in a scheduled notification summary
- Low Power Mode is off while testing

**Manual curl test works but Claude never notifies:**

```bash
python3 -m json.tool ~/.claude/settings.json
```

confirms the file is valid JSON, then run `/hooks` inside Claude Code to confirm the hooks are loaded, and fully restart Claude Code (`/exit`, then `claude`) — hooks are only read at session start.

## Security note

Your Bark device key is effectively a password — anyone with it can push notifications to your phone. `install.sh` only asks for it interactively and writes it into your local `~/.claude/settings.json`; it is never written anywhere in this repo. If you ever paste it somewhere public, regenerate it in the Bark app, re-run `./install.sh`, and remove the old hooks with `./uninstall.sh` first if needed.

## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 3: Commit**

```bash
git add LICENSE README.md
git commit -m "Add LICENSE and README"
```

---

### Task 2: install.sh

**Files:**
- Create: `install.sh`
- Test: `test/install_test.sh` (bash test harness, run manually — see steps below; not shipped as a CI job per the spec's non-goals)

**Interfaces:**
- Produces: `install.sh` executable that takes no arguments, prompts for the device key on stdin, and writes hooks with `group=claude-pager` into `$HOME/.claude/settings.json`. Honors `$HOME` so tests can redirect it to a scratch directory.
- Consumes: nothing from other tasks.

- [ ] **Step 1: Write the test harness**

Create `test/install_test.sh`:

```bash
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
```

Make it executable: `chmod +x test/install_test.sh`.

- [ ] **Step 2: Run the test harness to verify it fails (install.sh doesn't exist yet)**

Run: `bash test/install_test.sh`
Expected: FAIL with `install.sh: No such file or directory` (or `Permission denied`).

- [ ] **Step 3: Write install.sh**

```bash
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
```

Make it executable: `chmod +x install.sh`.

- [ ] **Step 4: Run the test harness to verify it passes**

Run: `bash test/install_test.sh`
Expected: `All install.sh cases passed`

- [ ] **Step 5: Commit**

```bash
git add install.sh test/install_test.sh
git commit -m "Add install.sh with hook-merge tests"
```

---

### Task 3: uninstall.sh

**Files:**
- Create: `uninstall.sh`
- Test: `test/uninstall_test.sh`

**Interfaces:**
- Consumes: the `settings.json` shape produced by Task 2's `install.sh` (hook entries identified by `group=claude-pager` in the `command` string).
- Produces: `uninstall.sh` executable, no arguments, honors `$HOME`.

- [ ] **Step 1: Write the test harness**

Create `test/uninstall_test.sh`:

```bash
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
      {"matcher": "", "hooks": [{"type": "command", "command": "curl '\''https://api.day.app/KEY/Claude%20Finished/x?sound=glass&group=claude-pager'\''", "async": true}]}
    ],
    "Notification": [
      {"matcher": "", "hooks": [{"type": "command", "command": "curl '\''https://api.day.app/KEY/Claude%20Needs%20You/x?sound=minuet&group=claude-pager'\''", "async": true}]}
    ]
  }
}
JSON
HOME="$tmp_home" "$SCRIPT_DIR/uninstall.sh" >/tmp/uninstall_out.txt 2>&1
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
HOME="$tmp_home" "$SCRIPT_DIR/uninstall.sh" >/tmp/uninstall_out2.txt 2>&1
grep -q "nothing to uninstall" /tmp/uninstall_out2.txt
rm -rf "$tmp_home"

echo "All uninstall.sh cases passed"
```

Make it executable: `chmod +x test/uninstall_test.sh`.

- [ ] **Step 2: Run the test harness to verify it fails (uninstall.sh doesn't exist yet)**

Run: `bash test/uninstall_test.sh`
Expected: FAIL with `uninstall.sh: No such file or directory` (or `Permission denied`).

- [ ] **Step 3: Write uninstall.sh**

```bash
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

BACKUP_FILE="${SETTINGS_FILE}.bak.$(date +%s)"
cp "$SETTINGS_FILE" "$BACKUP_FILE"
echo "Backed up existing settings to $BACKUP_FILE"

python3 - "$SETTINGS_FILE" <<'PYEOF'
import json
import sys

settings_path = sys.argv[1]

with open(settings_path) as f:
    data = json.load(f)

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

if ! python3 -c "import json; json.load(open('$SETTINGS_FILE'))" >/dev/null 2>&1; then
  echo "Error: wrote invalid JSON to $SETTINGS_FILE." >&2
  cp "$BACKUP_FILE" "$SETTINGS_FILE"
  echo "Restored previous settings from backup." >&2
  exit 1
fi

echo "claude-pager hooks removed from $SETTINGS_FILE"
```

Make it executable: `chmod +x uninstall.sh`.

- [ ] **Step 4: Run the test harness to verify it passes**

Run: `bash test/uninstall_test.sh`
Expected: `All uninstall.sh cases passed`

- [ ] **Step 5: Commit**

```bash
git add uninstall.sh test/uninstall_test.sh
git commit -m "Add uninstall.sh with hook-removal tests"
```

---

### Task 4: End-to-end verification and publish

**Files:**
- Modify: none (verification only)

**Interfaces:**
- Consumes: `install.sh` and `uninstall.sh` from Tasks 2–3.

- [ ] **Step 1: Run both test harnesses together**

Run:
```bash
bash test/install_test.sh && bash test/uninstall_test.sh
```
Expected: both print their "All ... cases passed" lines, exit 0.

- [ ] **Step 2: Manual real-device smoke test (requires an actual Bark device key)**

Run `./install.sh` for real (no `CLAUDE_PAGER_SKIP_CURL`), paste a real device key, confirm the "Installed successfully" push arrives on the phone, then confirm `~/.claude/settings.json` contains the three `group=claude-pager` hooks via:
```bash
python3 -m json.tool ~/.claude/settings.json
```
Then run `./uninstall.sh` and confirm the hooks are gone but any pre-existing personal settings remain.

- [ ] **Step 3: Push to GitHub**

```bash
git push origin main
```

- [ ] **Step 4: Verify on GitHub**

Confirm at `https://github.com/AaritKumar/claude-pager` that `main` is the default branch, the LICENSE is auto-detected by GitHub as MIT, and the README renders correctly.
