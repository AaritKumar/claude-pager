# claude-pager

Get an iPhone push notification the moment [Claude Code](https://claude.com/claude-code) needs your input, finishes a response, or hits an error — powered by [Bark](https://apps.apple.com/app/bark-customed-notifications/id1403753865).

| Claude Code event | Notification |
|---|---|
| Needs your attention/input | **Claude Needs You** (sound: minuet) |
| Finishes responding | **Claude Finished** (sound: glass) |
| Stops on an error | **Claude Stopped** (sound: alarm) |

All three are grouped under `claude-pager` on your phone.

## Requirements

- macOS or Linux (on Windows, run this from WSL or Git Bash — both provide the `bash`/`curl`/`python3` this needs)
- [Claude Code](https://claude.com/claude-code) >= 2.1.78 (for `StopFailure` hook support)
- `curl` and `python3` (both ship with macOS; install via your package manager on Linux, e.g. `apt install curl python3`)
- An iPhone with [Bark – Custom Notifications](https://apps.apple.com/app/bark-customed-notifications/id1403753865) installed, with notifications allowed

## Install

```bash
git clone https://github.com/AaritKumar/claude-pager.git
cd claude-pager
./install.sh
```

Open Bark on your iPhone, copy the device key it shows you (looks like `https://api.day.app/YOUR_DEVICE_KEY/`), and paste it when `install.sh` asks for it — only the key itself is required, but pasting the whole URL Bark shows you works too, since `install.sh` strips the surrounding URL automatically.

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
