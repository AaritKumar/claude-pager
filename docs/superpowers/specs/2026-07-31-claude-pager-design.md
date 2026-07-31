# claude-pager — Design

## Purpose

`claude-pager` sends Bark push notifications to an iPhone when Claude Code:

- needs the user's attention or input,
- finishes responding, or
- stops because of an error.

It packages the manual "edit `~/.claude/settings.json` by hand" workflow into a one-command installer, and publishes it as an open-source (MIT) macOS utility.

## Non-goals

- No support for notification services other than Bark in v1 (YAGNI — Bark-only, matching the original workflow this replaces).
- No CI, no CONTRIBUTING.md, no automated test suite — this is a small, host-modifying shell utility tested manually against representative `settings.json` states.
- No Linux/Windows support (Claude Code hooks + this notification flow are being packaged for macOS, matching the original doc's scope).

## Repo layout

```
claude-pager/
├── README.md
├── LICENSE               # MIT
├── install.sh
└── uninstall.sh
```

## install.sh

1. **Preflight checks** — verify `curl` and `python3` are on PATH; verify `uname` reports Darwin. Exit non-zero with a clear message if not.
2. **Prompt for the Bark device key** — `read -p "Paste your Bark device key: "`. Reject empty input.
3. **Test the key** — send a real Bark notification (`Claude Pager` / `Installed successfully`, sound `minuet`) via `curl`. If the curl call fails (non-2xx or network error), print an error and abort before touching any files.
4. **Prepare `~/.claude/settings.json`**:
   - `mkdir -p ~/.claude`.
   - If `settings.json` already exists, copy it to `settings.json.bak.<unix-timestamp>` before modifying.
   - If it doesn't exist, start from `{}`.
5. **Merge hooks** via an embedded `python3 -c` snippet (not `sed`/manual string editing, to avoid corrupting existing JSON):
   - Load the JSON (or `{}`).
   - Ensure `hooks` key exists as a dict.
   - For each of `Notification`, `Stop`, `StopFailure`: check whether a hook entry with `group=claude-pager` already exists in that event's hook list (idempotency — re-running install.sh should not duplicate entries). If not present, append the claude-pager hook block (matcher `""`, command using the entered device key, `async: true`).
   - Write the merged JSON back with `indent=2`.
6. **Validate** — reload the written file with `json.load` to confirm it's valid JSON; if not, restore from the backup made in step 4 and exit non-zero.
7. **Print next steps** — remind the user to restart Claude Code and run `/hooks` to confirm, and to test with "Reply with the word done."

### Hook naming change from the original handoff doc

The Bark notification `group` changes from `claude-code` to `claude-pager`. This is the identifier `install.sh`/`uninstall.sh` use to recognize "their" hook entries among any other hooks the user may already have configured, so install/uninstall never touch unrelated entries. Titles, bodies, and sounds otherwise match the original doc (`Claude Needs You` / `minuet`, `Claude Finished` / `glass`, `Claude Stopped` / `alarm`).

## uninstall.sh

1. Preflight-checks `python3` is available.
2. If `~/.claude/settings.json` doesn't exist, print "nothing to uninstall" and exit 0.
3. Back up `settings.json` (timestamped, same convention as install.sh).
4. Embedded `python3` snippet: for each of `Notification`/`Stop`/`StopFailure`, remove only hook entries whose command contains `group=claude-pager`; drop the event key entirely if its list becomes empty; drop the `hooks` key entirely if it becomes empty. Leave all other settings untouched.
5. Validate resulting JSON; write back; print confirmation.

## README.md contents

- One-paragraph pitch + what the three notifications look like.
- Requirements (macOS, Claude Code, curl, iPhone with Bark app).
- Install: `git clone` + `./install.sh` (or a `curl | bash` one-liner pointing at `install.sh` on `main`).
- Uninstall: `./uninstall.sh`.
- How it works (brief explanation of Claude Code hooks + Bark, linking the two).
- Troubleshooting section (validate JSON manually, `/hooks`, iPhone notification settings, sound test), condensed from the original handoff doc.
- Security note: the Bark device key is equivalent to a password; it's entered interactively and stored only in the user's local `~/.claude/settings.json`, never in this repo.

## Error handling

Every failure path (missing dependency, bad device key, invalid existing JSON, failed backup) prints a one-line, human-readable error and exits non-zero without leaving `settings.json` partially written. The pre-write JSON validation + backup-restore-on-failure in install.sh step 6 is the key safety net.

## Testing plan (manual, pre-release)

Run `install.sh` against three local `~/.claude/settings.json` fixtures before publishing:
1. No existing file.
2. Existing file with unrelated settings/hooks (confirm they're preserved).
3. File already containing claude-pager hooks (confirm idempotent re-run, no duplicates).

Then run `uninstall.sh` against the result of each and confirm only claude-pager entries are removed.
