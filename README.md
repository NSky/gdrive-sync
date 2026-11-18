# gdrive-sync

**Bidirectional Google Drive sync for Linux with real-time watching of local and remote changes.**

A complete solution for keeping a local directory in sync with Google Drive using [rclone's bisync](https://rclone.org/bisync/). Features automatic conflict resolution, real-time monitoring of local and Drive changes, and robust error recovery.

> **Note:** This project is based on the [namastexlabs/linux-gdrive-sync](https://github.com/namastexlabs/linux-gdrive-sync) repository.

## Features

- **Bidirectional sync**: Changes flow both ways - local to Drive, and Drive to local
- **Real-time local watching**: Uses `inotifywait` to detect and sync local changes immediately
- **Real-time remote watching**: Follows Google Drive's change feed and syncs only when something changed on Drive
- **Safety-net timer**: A slower periodic sync catches anything the watchers missed
- **Smart conflict resolution**: Newest file wins, with dated backup of conflicts
- **Auto-recovery**: Automatic full resync after consecutive failures
- **Stale lock detection**: Automatically cleans up locks from crashed processes
- **JSON status API**: Easy monitoring with `status.json`
- **Log rotation**: Keeps logs tidy with 7-day retention
- **Systemd integration**: Runs as user services, starts on boot

## Installation

### Arch Linux

The package is available in the AUR as [nsky-gdrive-sync](https://aur.archlinux.org/packages/nsky-gdrive-sync). Install it with an AUR helper:

```bash
yay -S nsky-gdrive-sync      # or: paru -S nsky-gdrive-sync
```

or manually:

```bash
git clone https://aur.archlinux.org/nsky-gdrive-sync.git
cd nsky-gdrive-sync
makepkg -si
```

### Other distributions (from source)

Install the dependencies (`rclone`, `inotify-tools`, `jq`) with your package manager, then:

```bash
git clone https://github.com/NSky/gdrive-sync.git
cd gdrive-sync
sudo make install            # PREFIX=/usr by default
```

Installation puts the scripts in `/usr/bin` and the systemd **user** units in `/usr/lib/systemd/user`, so every user on the machine can use them. Nothing is enabled or started by the install, and upgrades never change whether the services are enabled or running.

### Per-user setup

Each user who wants to sync their Google Drive runs, as themselves (not root):

```bash
gdrive-sync-setup
```

The setup will:
1. Check the dependencies (rclone, inotify-tools, jq)
2. Guide you through configuration (`~/.config/gdrive-sync/config.env`)
3. Set up your rclone Google Drive remote (if needed)
4. Optionally run the initial sync
5. Optionally enable and start the sync services for your account

Every user's services run under their own account with `systemctl --user`, using their own config, state and rclone remote.

## Prerequisites

- **Linux** with systemd (user services)
- **rclone** >= 1.58 (for bisync support)
- **inotify-tools** (for file watching)
- **jq** (for JSON status)

## Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │                Google Drive                  │
                    └─────────────────────────────────────────────┘
                          ▲                          │
                          │ rclone bisync            │ change feed
                          │                          ▼
┌───────────────────────────────────────────────────────────────────┐
│                         Your Linux Machine                         │
│                                                                     │
│  ┌─────────────────┐  ┌────────────────────┐  ┌─────────────────┐  │
│  │ gdrive-sync-    │  │ gdrive-sync.timer  │  │ gdrive-sync-    │  │
│  │ watch           │  │ (every 15 min,     │  │ remote-watch    │  │
│  │ (inotifywait on │  │  safety net)       │  │ (rclone change- │  │
│  │  ~/gdrive)      │  │                    │  │  notify)        │  │
│  └────────┬────────┘  └─────────┬──────────┘  └────────┬────────┘  │
│           │ triggers            │ triggers             │ triggers  │
│           ▼                     ▼                      ▼           │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                gdrive-sync (incremental bisync)              │  │
│  └─────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

### How It Works

1. **gdrive-sync-watch** (always running): Monitors local directory for file changes using inotifywait. When changes are detected, it triggers gdrive-sync after a 5-second debounce.

2. **gdrive-sync-remote-watch** (always running): Follows Google Drive's change feed with `rclone test changenotify`, asking Drive for changes every 30 seconds. Each check is a single small API request instead of a listing of the whole tree. When Drive reports a change, it triggers gdrive-sync after a short debounce, and at most once a minute while changes keep arriving (for example, while someone edits a document in the browser).

3. **gdrive-sync** (on a trigger, and every 15 minutes as a safety net): Runs incremental bisync to catch remote changes and push any pending local changes. Handles conflicts, locking, and auto-recovery. Only one sync runs at a time: if a sync is already in progress, the next run is skipped.

4. **gdrive-sync --resync** (on demand): Performs a full resync to rebuild the sync baseline. Run it after first setup, after changing the filters, or to recover from a broken state. It waits for a running sync to finish rather than skipping. `gdrive-sync` also runs a resync on its own after repeated failures.

## Configuration

Configuration is stored in `~/.config/gdrive-sync/config.env`. `gdrive-sync-setup` creates it for you; to configure manually, create the file yourself. Every setting is optional — anything left out uses the default shown below. The scripts read a different file if you set `GDRIVE_CONFIG=/path/to/config.env`.

After changing the configuration, restart the watchers so they pick up the new values:

```bash
systemctl --user restart gdrive-sync-watch.service gdrive-sync-remote-watch.service
```

Settings and their defaults:

```bash
# Local directory to sync
GDRIVE_LOCAL="$HOME/gdrive"

# rclone remote name
GDRIVE_REMOTE="gdrive:"

# State directory (logs, status, locks)
GDRIVE_STATE_DIR="$HOME/.local/state/gdrive-sync"

# Bisync filters file
GDRIVE_FILTERS="$HOME/.config/gdrive-sync/bisync-filters.txt"

# Max failures before auto-resync
GDRIVE_MAX_FAILURES=6

# Lock timeout (minutes); stale locks older than this are removed
GDRIVE_LOCK_TIMEOUT=10

# Debounce delay for both watchers (seconds)
GDRIVE_DEBOUNCE_SEC=5

# How often the remote watcher asks Google Drive for changes (seconds)
GDRIVE_POLL_SEC=30

# Minimum time between syncs triggered by remote changes (seconds)
GDRIVE_REMOTE_MIN_INTERVAL_SEC=60
```

### Remote Change Watching

`gdrive-sync-remote-watch` relies on `rclone test changenotify`. Google Drive supports it, but not every rclone backend does: on a remote without a change feed the watcher logs an error and stops, and remote changes are picked up by the 15-minute timer only. `rclone test` is meant for debugging, so a future rclone release could change its output; the timer keeps your files in sync if that happens.

Uploads made by gdrive-sync itself also show up in Drive's change feed, so a local change is usually followed by one extra sync that finds nothing to do.

To check remote changes more or less often than every 15 minutes without the watcher, override the timer:

```bash
systemctl --user edit gdrive-sync.timer
# [Timer]
# OnUnitActiveSec=
# OnUnitActiveSec=5min
```

### Excluding Files

Edit `~/.config/gdrive-sync/bisync-filters.txt` to exclude files from syncing:

```
# Exclude large files
- huge-video.mp4
- *.iso

# Exclude temporary files
- ~$*
- *.tmp
- *.swp

# Include everything else
+ **
```

After changing the filters, run `gdrive-sync --resync` once: rclone bisync needs a fresh baseline whenever the filters change.

See [rclone filtering documentation](https://rclone.org/filtering/) for syntax details.

## Usage

### Manual Commands

```bash
# Run an immediate sync
gdrive-sync

# Force a full resync (recovery, or after changing filters)
gdrive-sync --resync

# Check sync status
cat ~/.local/state/gdrive-sync/status.json

# View recent logs
ls -la ~/.local/state/gdrive-sync/logs/
```

### Service Management

```bash
# Check service status
systemctl --user status gdrive-sync.timer
systemctl --user status gdrive-sync-watch.service
systemctl --user status gdrive-sync-remote-watch.service

# View service logs
journalctl --user -u gdrive-sync.service -f
journalctl --user -u gdrive-sync-watch.service -f
journalctl --user -u gdrive-sync-remote-watch.service -f

# Restart services
systemctl --user restart gdrive-sync.timer
systemctl --user restart gdrive-sync-watch.service gdrive-sync-remote-watch.service

# Temporarily disable sync
systemctl --user stop gdrive-sync.timer
systemctl --user stop gdrive-sync-watch.service gdrive-sync-remote-watch.service
```

## Status Monitoring

The sync status is stored as JSON for easy parsing:

```bash
cat ~/.local/state/gdrive-sync/status.json
```

Example output:
```json
{
  "status": "success",
  "mode": "sync",
  "message": "Sync OK",
  "consecutive_failures": 0,
  "last_success": "2025-01-15T10:30:00+00:00",
  "last_resync": "2025-01-10T09:00:00+00:00",
  "updated_at": "2025-01-15T10:30:00+00:00",
  "log_file": "/home/user/.local/state/gdrive-sync/logs/sync_20250115_103000.log"
}
```

`mode` is `sync` for incremental runs and `resync` for full resyncs (requested with `--resync` or started automatically after repeated failures). `last_resync` is the time of the last successful resync.

### Status Values

| Status | Meaning |
|--------|---------|
| `success` | Last sync completed successfully |
| `running` | Sync currently in progress |
| `error` | Last sync failed |

## Troubleshooting

### Sync keeps failing

Check the logs:
```bash
tail -f ~/.local/state/gdrive-sync/logs/sync_*.log
```

Resync runs log to `resync_*.log` in the same directory.

After 6 consecutive failures, the system will automatically attempt a full resync.

### "Permission denied" or authentication errors

Re-authenticate with rclone:
```bash
rclone config reconnect gdrive:
```

### Stale lock errors

If sync complains about locks, it will auto-clear them after 10 minutes. To clear manually:
```bash
rm -f ~/.cache/rclone/bisync/*.lck
```

### Force a fresh start

To reset everything and re-establish the sync baseline:
```bash
# Stop services
systemctl --user stop gdrive-sync.timer gdrive-sync-watch.service gdrive-sync-remote-watch.service

# Clear rclone bisync state
rm -rf ~/.cache/rclone/bisync/

# Run fresh initial sync
gdrive-sync --resync

# Restart services
systemctl --user start gdrive-sync.timer gdrive-sync-watch.service gdrive-sync-remote-watch.service
```

## Uninstall

First, each user who enabled the services disables them:

```bash
systemctl --user disable --now gdrive-sync.timer gdrive-sync-watch.service gdrive-sync-remote-watch.service
```

Then remove the package (`sudo pacman -R nsky-gdrive-sync` on Arch, or `sudo make uninstall` from the source tree).

Your synced data, configuration and rclone remote are kept.

## File Locations

| Path | Description |
|------|-------------|
| `/usr/bin/gdrive-*` | Sync scripts and `gdrive-sync-setup` |
| `/usr/lib/systemd/user/gdrive-*.{service,timer}` | Systemd user units (shared by all users) |
| `/usr/share/gdrive-sync/` | Default filters |
| `~/.config/gdrive-sync/config.env` | Per-user configuration |
| `~/.config/gdrive-sync/bisync-filters.txt` | Per-user exclusion filters (falls back to the default) |
| `~/.local/state/gdrive-sync/` | State directory |
| `~/.local/state/gdrive-sync/logs/` | Sync logs |
| `~/.local/state/gdrive-sync/status.json` | Status file |
| `~/.cache/rclone/bisync/` | rclone bisync state |

## License

MIT License - see [LICENSE](LICENSE)

## Credits

Built with [rclone](https://rclone.org/) - a powerful command-line cloud sync tool.

---

**NSkyLabs** | [GitHub](https://github.com/NSky)
