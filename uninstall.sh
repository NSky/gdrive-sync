#!/bin/bash
# linux-gdrive-sync uninstaller
#
# This script removes linux-gdrive-sync from your system.
# Your synced data and rclone configuration will NOT be removed.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installation paths
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/gdrive-sync"
SYSTEMD_DIR="$HOME/.config/systemd/user"
STATE_DIR="$HOME/.local/state/gdrive-sync"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

main() {
    echo ""
    echo "=========================================="
    echo "  linux-gdrive-sync Uninstaller"
    echo "=========================================="
    echo ""

    echo "This will remove:"
    echo "  - Scripts from $BIN_DIR/"
    echo "  - Systemd services"
    echo ""
    echo "This will NOT remove:"
    echo "  - Your synced data (~/gdrive or configured directory)"
    echo "  - Your rclone configuration"
    echo ""

    read -rp "Continue with uninstall? [y/N]: " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        echo "Aborted."
        exit 0
    fi

    echo ""

    # Stop and disable services
    log_info "Stopping and disabling services..."

    systemctl --user stop gdrive-sync.timer 2>/dev/null || true
    systemctl --user stop gdrive-fullsync.timer 2>/dev/null || true
    systemctl --user stop gdrive-watch.service 2>/dev/null || true

    systemctl --user disable gdrive-sync.timer 2>/dev/null || true
    systemctl --user disable gdrive-sync.service 2>/dev/null || true
    systemctl --user disable gdrive-fullsync.timer 2>/dev/null || true
    systemctl --user disable gdrive-fullsync.service 2>/dev/null || true
    systemctl --user disable gdrive-watch.service 2>/dev/null || true

    log_success "Services stopped and disabled"

    # Remove systemd units
    log_info "Removing systemd units..."
    rm -f "$SYSTEMD_DIR/gdrive-sync.service"
    rm -f "$SYSTEMD_DIR/gdrive-sync.timer"
    rm -f "$SYSTEMD_DIR/gdrive-fullsync.service"
    rm -f "$SYSTEMD_DIR/gdrive-fullsync.timer"
    rm -f "$SYSTEMD_DIR/gdrive-watch.service"

    systemctl --user daemon-reload
    log_success "Systemd units removed"

    # Remove scripts
    log_info "Removing scripts..."
    rm -f "$BIN_DIR/gdrive-sync"
    rm -f "$BIN_DIR/gdrive-watch"
    rm -f "$BIN_DIR/gdrive-initial-resync"
    log_success "Scripts removed"

    # Ask about config and state
    echo ""
    read -rp "Remove configuration and state files? [y/N]: " remove_config
    if [[ "${remove_config,,}" == "y" ]]; then
        log_info "Removing configuration and state..."
        rm -rf "$CONFIG_DIR"
        rm -rf "$STATE_DIR"
        log_success "Configuration and state removed"
    else
        log_info "Keeping configuration at $CONFIG_DIR"
        log_info "Keeping state/logs at $STATE_DIR"
    fi

    echo ""
    echo "=========================================="
    log_success "Uninstallation complete!"
    echo "=========================================="
    echo ""
    echo "Your synced data was NOT removed."
    echo "Your rclone configuration was NOT removed."
    echo ""
}

main "$@"
