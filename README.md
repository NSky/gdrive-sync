# gdrive-sync

**Bidirectional Google Drive sync for Linux with real-time local file watching.**

A complete solution for keeping a local directory in sync with Google Drive using [rclone's bisync](https://rclone.org/bisync/). Features automatic conflict resolution, real-time monitoring of local changes, and robust error recovery.

> **Note:** This project is based on the [namastexlabs/linux-gdrive-sync](https://github.com/namastexlabs/linux-gdrive-sync) repository.

## Features

- **Bidirectional sync**: Changes flow both ways - local to Drive, and Drive to local
- **Real-time local watching**: Uses `inotifywait` to detect and sync local changes immediately
- **Periodic remote polling**: Timer-based polling catches changes made on Google Drive
- **Smart conflict resolution**: Newest file wins, with dated backup of conflicts
- **Auto-recovery**: Automatic full resync after consecutive failures
- **Stale lock detection**: Automatically cleans up locks from crashed processes
- **JSON status API**: Easy monitoring with `status.json`
- **Log rotation**: Keeps logs tidy with 7-day retention
- **Systemd integration**: Runs as user services, starts on boot

## Installation

### Arch Linux

```bash
git clone https://github.com/NSky/gdrive-sync.git
cd gdrive-sync/packaging/arch
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
                                         ▲
                                         │
                              rclone bisync
                                         │
                                         ▼
┌───────────────────────────────────────────────────────────────────┐
│                         Your Linux Machine                         │
│                                                                     │
│  ┌─────────────────┐   detects    ┌────────────────────────────┐  │
│  │ Local Directory │◄────────────►│     gdrive-sync-watch      │  │
│  │   ~/gdrive      │   changes    │  (inotifywait daemon)      │  │
│  └─────────────────┘              └────────────┬───────────────┘  │
│                                                │                   │
│                                     triggers   │                   │
│                                                ▼                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                      gdrive-sync                             │  │
│  │              (incremental bisync, 2min timer)                │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                   gdrive-fullsync                            │  │
│  │              (daily full resync at 3am)                      │  │
│  └─────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

### How It Works

1. **gdrive-sync-watch** (always running): Monitors local directory for file changes using inotifywait. When changes are detected, it triggers gdrive-sync after a 5-second debounce.

2. **gdrive-sync** (every 2 minutes): Runs incremental bisync to catch remote changes and push any pending local changes. Handles conflicts, stale locks, and auto-recovery.

3. **gdrive-fullsync** (daily at 3am): Performs a full `--resync` to ensure complete consistency, including any large files excluded from incremental syncs.

## Configuration

Configuration is stored in `~/.config/gdrive-sync/config.env`:

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

# Lock timeout (minutes)
GDRIVE_LOCK_TIMEOUT=10

# Debounce delay (seconds)
GDRIVE_DEBOUNCE_SEC=5
```

### Excluding Files

Edit `~/.config/gdrive-sync/bisync-filters.txt` to exclude files from incremental syncs:

```
# Exclude large files (will only sync during daily fullsync)
- huge-video.mp4
- *.iso

# Exclude temporary files
- ~$*
- *.tmp
- *.swp

# Include everything else
+ **
```

See [rclone filtering documentation](https://rclone.org/filtering/) for syntax details.

## Usage

### Manual Commands

```bash
# Run an immediate sync
gdrive-sync

# Force a full resync (recovery)
gdrive-sync-resync

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

# View service logs
journalctl --user -u gdrive-sync.service -f
journalctl --user -u gdrive-sync-watch.service -f

# Restart services
systemctl --user restart gdrive-sync.timer
systemctl --user restart gdrive-sync-watch.service

# Temporarily disable sync
systemctl --user stop gdrive-sync.timer
systemctl --user stop gdrive-sync-watch.service
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
  "message": "Sync OK",
  "consecutive_failures": 0,
  "last_success": "2025-01-15T10:30:00+00:00",
  "updated_at": "2025-01-15T10:30:00+00:00"
}
```

### Status Values

| Status | Meaning |
|--------|---------|
| `success` | Last sync completed successfully |
| `running` | Sync currently in progress |
| `error` | Last sync failed |
| `skipped` | Skipped (another sync was running) |

## Troubleshooting

### Sync keeps failing

Check the logs:
```bash
tail -f ~/.local/state/gdrive-sync/logs/sync_*.log
```

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
systemctl --user stop gdrive-sync.timer gdrive-sync-watch.service

# Clear rclone bisync state
rm -rf ~/.cache/rclone/bisync/

# Run fresh initial sync
gdrive-sync-resync

# Restart services
systemctl --user start gdrive-sync.timer gdrive-sync-watch.service
```

## Uninstall

First, each user who enabled the services disables them:

```bash
systemctl --user disable --now gdrive-sync.timer gdrive-fullsync.timer gdrive-sync-watch.service
```

Then remove the package (`sudo pacman -R gdrive-sync` on Arch, or `sudo make uninstall` from the source tree).

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
