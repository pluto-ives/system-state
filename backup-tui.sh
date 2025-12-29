#!/bin/bash
#
# Beautiful TUI for System State Backup
# Uses gum (https://github.com/charmbracelet/gum) for styling
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPTURE_SCRIPT="$SCRIPT_DIR/capture.sh"
BACKUP_DIR="${SYSTEM_STATE_BACKUP_DIR:-$HOME/system-state-backup}"

# Colors
CYAN="#7dcfff"
PURPLE="#bb9af7"
GREEN="#9ece6a"
YELLOW="#e0af68"
RED="#f7768e"
GRAY="#565f89"
WHITE="#c0caf5"

# Get last backup info
get_last_backup() {
    if [[ -d "$BACKUP_DIR/.git" ]]; then
        cd "$BACKUP_DIR"
        git log -1 --format="%ar" 2>/dev/null || echo "never"
    else
        echo "never"
    fi
}

# Get package counts
get_package_info() {
    local official=$(pacman -Qqen 2>/dev/null | wc -l)
    local aur=$(pacman -Qqem 2>/dev/null | wc -l)
    echo "$official official, $aur AUR"
}

# Header
show_header() {
    clear
    echo ""
    gum style \
        --foreground "$CYAN" \
        --border-foreground "$PURPLE" \
        --border double \
        --align center \
        --width 50 \
        --margin "0 2" \
        --padding "1 2" \
        "  SYSTEM STATE BACKUP" \
        "" \
        "Arch Linux Configuration Manager"
    echo ""
}

# Show system info
show_info() {
    local last_backup=$(get_last_backup)
    local packages=$(get_package_info)
    local hostname=$(hostname)
    local kernel=$(uname -r)

    gum style \
        --foreground "$GRAY" \
        --margin "0 4" \
        "$(gum style --foreground "$WHITE" "Hostname:")    $hostname"

    gum style \
        --foreground "$GRAY" \
        --margin "0 4" \
        "$(gum style --foreground "$WHITE" "Kernel:")      $kernel"

    gum style \
        --foreground "$GRAY" \
        --margin "0 4" \
        "$(gum style --foreground "$WHITE" "Packages:")    $packages"

    gum style \
        --foreground "$GRAY" \
        --margin "0 4" \
        "$(gum style --foreground "$WHITE" "Last Backup:") $(gum style --foreground "$YELLOW" "$last_backup")"

    echo ""
}

# Show what will be backed up
show_backup_info() {
    gum style \
        --foreground "$WHITE" \
        --margin "0 4" \
        --padding "0 0" \
        "This backup will capture:"

    echo ""

    gum style \
        --foreground "$GREEN" \
        --margin "0 6" \
        "$(gum style --foreground "$CYAN" "")  Installed packages (pacman + AUR)"

    gum style \
        --foreground "$GREEN" \
        --margin "0 6" \
        "$(gum style --foreground "$CYAN" "")  User configs (~/.config/*)"

    gum style \
        --foreground "$GREEN" \
        --margin "0 6" \
        "$(gum style --foreground "$CYAN" "")  System configs (/etc/*)"

    gum style \
        --foreground "$GREEN" \
        --margin "0 6" \
        "$(gum style --foreground "$CYAN" "")  Enabled systemd services"

    gum style \
        --foreground "$GREEN" \
        --margin "0 6" \
        "$(gum style --foreground "$CYAN" "")  Push to GitHub"

    echo ""
}

# Run backup with spinner
run_backup() {
    echo ""
    gum style \
        --foreground "$YELLOW" \
        --margin "0 4" \
        "  Sudo required for system configs"
    echo ""

    # Run the backup
    if sudo "$CAPTURE_SCRIPT"; then
        echo ""
        gum style \
            --foreground "$GREEN" \
            --border-foreground "$GREEN" \
            --border rounded \
            --align center \
            --width 46 \
            --margin "0 4" \
            --padding "1 2" \
            "  Backup Complete!" \
            "" \
            "Your system state has been saved and pushed to GitHub."
    else
        echo ""
        gum style \
            --foreground "$RED" \
            --border-foreground "$RED" \
            --border rounded \
            --align center \
            --width 46 \
            --margin "0 4" \
            --padding "1 2" \
            "  Backup Failed" \
            "" \
            "Check the output above for errors."
    fi
}

# Main menu
main_menu() {
    echo ""

    local choice=$(gum choose \
        --cursor.foreground "$CYAN" \
        --selected.foreground "$PURPLE" \
        --item.foreground "$WHITE" \
        --header.foreground "$GRAY" \
        --header "What would you like to do?" \
        "  Run Backup Now" \
        "  View Last Backup" \
        "  Skip for Now" \
        "  Exit")

    case "$choice" in
        *"Run Backup"*)
            run_backup
            echo ""
            gum style --foreground "$GRAY" --margin "0 4" "Press any key to exit..."
            read -n 1 -s
            ;;
        *"View Last"*)
            view_last_backup
            main_menu
            ;;
        *"Skip"*)
            echo ""
            gum style \
                --foreground "$YELLOW" \
                --margin "0 4" \
                "  Skipped. You can run manually anytime:"
            gum style \
                --foreground "$GRAY" \
                --margin "0 6" \
                "sudo ~/Projects/system-state/capture.sh"
            echo ""
            sleep 2
            ;;
        *"Exit"*)
            exit 0
            ;;
    esac
}

# View last backup details
view_last_backup() {
    show_header

    if [[ ! -d "$BACKUP_DIR/.git" ]]; then
        gum style \
            --foreground "$YELLOW" \
            --margin "0 4" \
            "No backups found yet. Run a backup first!"
        echo ""
        gum style --foreground "$GRAY" --margin "0 4" "Press any key to continue..."
        read -n 1 -s
        show_header
        show_info
        show_backup_info
        return
    fi

    cd "$BACKUP_DIR"

    gum style \
        --foreground "$WHITE" \
        --margin "0 4" \
        "Recent backup history:"
    echo ""

    git log --oneline -5 | while read -r line; do
        gum style \
            --foreground "$GRAY" \
            --margin "0 6" \
            "  $line"
    done

    echo ""

    if [[ -f "$BACKUP_DIR/packages/all-explicit.txt" ]]; then
        local pkg_count=$(wc -l < "$BACKUP_DIR/packages/all-explicit.txt")
        gum style \
            --foreground "$GREEN" \
            --margin "0 4" \
            "  $pkg_count packages tracked"
    fi

    echo ""
    gum style --foreground "$GRAY" --margin "0 4" "Press any key to continue..."
    read -n 1 -s

    show_header
    show_info
    show_backup_info
}

# Main
main() {
    # Check for gum
    if ! command -v gum &>/dev/null; then
        echo "Error: gum is required. Install with: pacman -S gum"
        exit 1
    fi

    show_header
    show_info
    show_backup_info
    main_menu
}

main "$@"
