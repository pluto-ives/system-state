#!/bin/bash
#
# Opens a terminal prompting the user to run the system state backup
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPTURE_SCRIPT="$SCRIPT_DIR/capture.sh"

# Use ghostty if available, fall back to other terminals
if command -v ghostty &>/dev/null; then
    ghostty -e bash -c "
        echo '========================================'
        echo '  Weekly System State Backup Reminder'
        echo '========================================'
        echo ''
        echo 'It'\''s time to backup your system state!'
        echo ''
        echo 'This will:'
        echo '  - Capture all installed packages'
        echo '  - Backup your config files'
        echo '  - Save enabled services'
        echo '  - Push to GitHub'
        echo ''
        echo 'The backup requires sudo for system configs.'
        echo ''
        read -p 'Run backup now? [Y/n] ' -n 1 -r
        echo ''
        if [[ ! \$REPLY =~ ^[Nn]$ ]]; then
            echo ''
            sudo $CAPTURE_SCRIPT
            echo ''
            echo 'Press any key to close...'
            read -n 1
        fi
    "
elif command -v kitty &>/dev/null; then
    kitty -e bash -c "
        echo 'Weekly System State Backup Reminder'
        echo ''
        read -p 'Run backup now? [Y/n] ' -n 1 -r
        echo ''
        if [[ ! \$REPLY =~ ^[Nn]$ ]]; then
            sudo $CAPTURE_SCRIPT
            echo 'Press any key to close...'
            read -n 1
        fi
    "
elif command -v alacritty &>/dev/null; then
    alacritty -e bash -c "
        echo 'Weekly System State Backup Reminder'
        read -p 'Run backup now? [Y/n] ' -n 1 -r
        echo ''
        if [[ ! \$REPLY =~ ^[Nn]$ ]]; then
            sudo $CAPTURE_SCRIPT
            read -n 1
        fi
    "
else
    # Fallback: just send a notification
    notify-send "System State Backup" "Run: sudo ~/Projects/system-state/capture.sh" --urgency=normal
fi
