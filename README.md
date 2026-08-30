# Ripcord

Pair a USB drive to your machine and carry it on a lanyard. If the drive is
pulled out, the session locks — and, if you ask it to, the machine goes to
sleep.

The idea is a failsafe for working in public: the drive is tethered to you, so
if the laptop is snatched it comes apart and the machine is behind a password
prompt before it has left the table. It is a deterrent against a
snatch-and-run, not a defence against someone who has the machine and time.

The concept is borrowed from [RipCord](https://github.com/kclose3/RipCord), a
macOS project by [KClose](https://github.com/kclose3). This is an independent
implementation for Omarchy and shares no code with it.

## What it does

- **Pairs to a drive, not a name.** The key is the filesystem's unique
  identifier, so relabelling a drive does not break the pairing and a drive
  named to match yours cannot stand in for it.
- **Only offers drives you can physically pull out.** Devices reached over USB,
  and anything the kernel reports as removable. The disk your system runs from
  is never offered.
- **Watches for events rather than polling.** It is told when the set of
  attached drives changes, and re-reads to confirm. A slow re-read runs as a
  backstop so a missed event cannot leave the trap blind.
- **Shows its state in the bar.** A closed padlock when armed, open when not,
  and the icon turns urgent when arming would really lock the machine.
- **Rehearses.** Rehearsal mode is on by default: pulling the drive sends a
  notification describing what would have happened, and does nothing else.
- **Never re-arms by itself.** Arming is deliberate, is not written to disk,
  and does not survive a restart or a reload. Once it has fired, the drive has
  to be plugged back in before it can be armed again.

## Requirements

Python 3, which Omarchy already has. Nothing else — the drive watching uses
kernel facilities reached through the C library, so there is no watcher package
to install.

## Install

```bash
omarchy plugin add https://github.com/weedwhitesandwine/ripcord.git --enable
```

Then add **Ripcord** to your bar from the shell's bar settings, open it, plug
your drive in, and press the drive in the list to pair it.

## Update

```bash
omarchy plugin update io.github.weedwhitesandwine.ripcord
```

## Remove

```bash
omarchy plugin remove io.github.weedwhitesandwine.ripcord
```

Removing the plugin leaves your settings behind at
`~/.local/state/omarchy/ripcord/`. Delete that directory to clear them.

## What it writes, and when

**Files it writes**

| Path | When | What |
|---|---|---|
| `~/.local/state/omarchy/ripcord/settings.json` | When you pair, unpair, or change a setting | The paired drive's identifier and label, and the three toggles |

The state directory is created with owner-only permissions. Writes go through
the shell's atomic-write path. Whether the trap is armed is deliberately *not*
written anywhere.

**Files it reads**

| Path | Why |
|---|---|
| `/dev/disk/by-uuid`, `/dev/disk/by-label` | To see which filesystems are attached and what they are called |
| `/sys/class/block/...` | To tell a drive you can pull out from one that is bolted in |
| its own `settings.json` | To restore your pairing and settings |

Its own settings file is opened without following symlinks, checked to be a
regular file, and read to a fixed ceiling, so a file that has been replaced
with something else yields nothing rather than something.

**Processes it runs**

| Command | When |
|---|---|
| `python3 ripcord-watch.py` | Once, for the life of the shell — the drive watcher |
| `loginctl lock-session`, falling back to `hyprlock` | When the trap fires and locking is enabled |
| `systemctl suspend` | When the trap fires and sleeping is enabled (off by default) |
| `notify-send` | On a rehearsal trigger, and if the watcher stops while armed |
| `mkdir -p -m 700` | Once at startup, for the state directory |

Every one of these runs as you, with your own session's permissions. The
watcher is started with `setpriv --pdeathsig TERM` so it cannot outlive the
shell.

**Network**

None. Ripcord does not open sockets and makes no requests.

## Limits worth knowing

Ripcord runs inside the desktop shell. If the shell stops, the watching stops
with it — the bar icon exists so the armed state is visible rather than assumed.
If the watcher process itself stops while armed, Ripcord says so in the bar and
sends a notification rather than quietly appearing to still be on guard.

A drive can be unplugged and replaced faster than any watcher can respond. This
is a tripwire, not a lock.

## Development

`test-classify.py` covers the drive classification — which devices count as
unpluggable — against synthetic device trees, including the cases real hardware
cannot produce on demand.

```bash
python3 test-classify.py
```

## Licence

MIT. See [LICENSE](LICENSE).

Built with [Claude Code](https://claude.com/claude-code).
