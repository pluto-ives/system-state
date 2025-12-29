#!/bin/bash
#
# Launches the System State Backup TUI in a floating terminal
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TUI_SCRIPT="$SCRIPT_DIR/backup-tui.sh"

# Terminal window settings
TITLE="System State Backup"
COLS=60
ROWS=28

# Launch in preferred terminal
if command -v ghostty &>/dev/null; then
    ghostty \
        --title="$TITLE" \
        --initial-columns="$COLS" \
        --initial-rows="$ROWS" \
        --class="system-state-backup" \
        -e "$TUI_SCRIPT"

elif command -v kitty &>/dev/null; then
    kitty \
        --title "$TITLE" \
        -o initial_window_width="${COLS}c" \
        -o initial_window_height="${ROWS}c" \
        "$TUI_SCRIPT"

elif command -v alacritty &>/dev/null; then
    alacritty \
        --title "$TITLE" \
        --option "window.dimensions.columns=$COLS" \
        --option "window.dimensions.lines=$ROWS" \
        -e "$TUI_SCRIPT"

elif command -v foot &>/dev/null; then
    foot \
        --title "$TITLE" \
        --window-size-chars "${COLS}x${ROWS}" \
        "$TUI_SCRIPT"

else
    # Fallback: notification
    notify-send "System State Backup" \
        "Run: ~/Projects/system-state/backup-tui.sh" \
        --urgency=normal \
        --icon=drive-harddisk
fi
