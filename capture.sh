#!/bin/bash
#
# System State Capture Tool for Arch Linux
# Captures packages, configs, and services to restore system state after reinstall
# Pushes to GitHub for offsite backup
#

set -uo pipefail

# Configuration
BACKUP_DIR="${SYSTEM_STATE_BACKUP_DIR:-$HOME/system-state-backup}"
GITHUB_REPO="${SYSTEM_STATE_GITHUB_REPO:-system-state-backup}"
PUSH_TO_GITHUB="${PUSH_TO_GITHUB:-true}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# User dotfiles/configs to backup (relative to $HOME)
USER_CONFIGS=(
    ".bashrc"
    ".bash_profile"
    ".profile"
    ".config/hypr"
    ".config/waybar"
    ".config/alacritty"
    ".config/kitty"
    ".config/ghostty"
    ".config/nvim"
    ".config/fish"
    ".config/starship.toml"
    ".config/mako"
    ".config/walker"
    ".config/btop"
    ".config/cava"
    ".config/fastfetch"
    ".config/lazygit"
    ".config/lazydocker"
    ".config/zathura"
    ".config/imv"
    ".config/fontconfig"
    ".config/mimeapps.list"
    ".config/chromium-flags.conf"
    ".config/brave-flags.conf"
    ".config/environment.d"
    ".config/autostart"
    ".config/uwsm"
    ".config/swayosd"
    ".config/elephant"
    ".config/mise"
    ".config/git"
    ".config/xdg-terminals.list"
    ".ssh/config"
)

# System configs to backup (requires sudo)
SYSTEM_CONFIGS=(
    "/etc/systemd/network"
    "/etc/mkinitcpio.conf"
    "/etc/locale.conf"
    "/etc/vconsole.conf"
    "/etc/hostname"
    "/etc/hosts"
    "/etc/fstab"
    "/etc/pacman.conf"
    "/etc/makepkg.conf"
    "/etc/ufw"
    "/etc/sddm.conf.d"
    "/etc/iwd"
    "/etc/modprobe.d"
    "/etc/sysctl.d"
    "/etc/X11/xorg.conf.d"
    "/etc/limine-entry-tool.conf"
    "/etc/limine-snapper-sync.conf"
    "/etc/snapper"
    "/etc/environment"
)

setup_backup_dir() {
    log_info "Setting up backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"/{packages,configs/user,configs/system,services,scripts}

    # Initialize git if not already
    if [[ ! -d "$BACKUP_DIR/.git" ]]; then
        log_info "Initializing git repository..."
        cd "$BACKUP_DIR"
        git init

        # Create .gitignore
        cat > .gitignore << 'EOF'
# Ignore large/binary files that shouldn't be tracked
*.log
*.tmp
*.cache
EOF

        # Create initial README
        cat > README.md << 'EOF'
# System State Backup

Automated backup of Arch Linux system configuration.

## Contents

- `packages/` - Installed package lists (official + AUR)
- `configs/user/` - User dotfiles and configs
- `configs/system/` - System configuration files
- `services/` - Enabled systemd services and custom units
- `restore.sh` - Interactive restore script

## Restore

```bash
./restore.sh
```
EOF
        git add .
        git commit -m "Initial commit"
    fi
}

setup_github_repo() {
    if [[ "$PUSH_TO_GITHUB" != "true" ]]; then
        return 0
    fi

    cd "$BACKUP_DIR"

    # Check if remote exists
    if ! git remote get-url origin &>/dev/null; then
        log_info "Setting up GitHub repository..."

        # Check if repo exists on GitHub
        if gh repo view "$GITHUB_REPO" &>/dev/null; then
            log_info "Connecting to existing GitHub repo: $GITHUB_REPO"
            git remote add origin "https://github.com/$(gh api user -q .login)/$GITHUB_REPO.git"
        else
            log_info "Creating private GitHub repo: $GITHUB_REPO"
            gh repo create "$GITHUB_REPO" --private --source=. --remote=origin --push
            return 0
        fi
    fi
}

capture_packages() {
    log_info "Capturing package lists..."

    # All explicitly installed packages
    pacman -Qqe > "$BACKUP_DIR/packages/all-explicit.txt"
    log_success "Explicit packages: $(wc -l < "$BACKUP_DIR/packages/all-explicit.txt")"

    # Official repo packages only
    pacman -Qqen > "$BACKUP_DIR/packages/official.txt"
    log_success "Official packages: $(wc -l < "$BACKUP_DIR/packages/official.txt")"

    # AUR/foreign packages
    pacman -Qqem > "$BACKUP_DIR/packages/aur.txt"
    log_success "AUR packages: $(wc -l < "$BACKUP_DIR/packages/aur.txt")"

    # Package groups
    pacman -Qg 2>/dev/null | cut -d' ' -f1 | sort -u > "$BACKUP_DIR/packages/groups.txt" || true

    # Packages with versions (for reference)
    pacman -Qe > "$BACKUP_DIR/packages/all-explicit-versions.txt"
}

capture_user_configs() {
    log_info "Capturing user configurations..."

    # Clean old configs first to catch deletions
    rm -rf "$BACKUP_DIR/configs/user/.config" "$BACKUP_DIR/configs/user/.bashrc" \
           "$BACKUP_DIR/configs/user/.bash_profile" "$BACKUP_DIR/configs/user/.profile" \
           "$BACKUP_DIR/configs/user/.ssh" 2>/dev/null || true

    local captured=0
    for config in "${USER_CONFIGS[@]}"; do
        local src="$HOME/$config"
        local dest="$BACKUP_DIR/configs/user/$config"

        if [[ -e "$src" ]]; then
            mkdir -p "$(dirname "$dest")"
            cp -a "$src" "$dest"
            ((captured++))
        fi
    done
    log_success "Captured $captured user config items"

    # Also capture list of all .config directories for reference
    ls -1 "$HOME/.config" > "$BACKUP_DIR/configs/user/config-dirs-list.txt" 2>/dev/null || true
}

capture_system_configs() {
    log_info "Capturing system configurations (requires sudo)..."

    # Clean old system configs first
    rm -rf "$BACKUP_DIR/configs/system/etc" 2>/dev/null || true
    mkdir -p "$BACKUP_DIR/configs/system/etc/pacman.d"

    local captured=0
    for config in "${SYSTEM_CONFIGS[@]}"; do
        if [[ -e "$config" ]]; then
            local dest="$BACKUP_DIR/configs/system$config"
            mkdir -p "$(dirname "$dest")"
            if sudo cp -a "$config" "$dest" 2>/dev/null; then
                # Fix ownership so git can read
                sudo chown -R "$USER:$USER" "$dest"
                ((captured++))
            else
                log_warn "Could not copy $config"
            fi
        fi
    done
    log_success "Captured $captured system config items"

    # Capture pacman mirrorlist
    if sudo cp /etc/pacman.d/mirrorlist "$BACKUP_DIR/configs/system/etc/pacman.d/mirrorlist" 2>/dev/null; then
        sudo chown "$USER:$USER" "$BACKUP_DIR/configs/system/etc/pacman.d/mirrorlist"
    fi
}

capture_services() {
    log_info "Capturing enabled services..."

    # User services
    systemctl --user list-unit-files --state=enabled --no-legend 2>/dev/null | \
        awk '{print $1}' > "$BACKUP_DIR/services/user-enabled.txt"
    log_success "User services: $(wc -l < "$BACKUP_DIR/services/user-enabled.txt")"

    # System services
    systemctl list-unit-files --state=enabled --no-legend | \
        awk '{print $1}' > "$BACKUP_DIR/services/system-enabled.txt"
    log_success "System services: $(wc -l < "$BACKUP_DIR/services/system-enabled.txt")"

    # Custom user service files
    rm -rf "$BACKUP_DIR/services/user-units" 2>/dev/null || true
    if [[ -d "$HOME/.config/systemd/user" ]]; then
        cp -a "$HOME/.config/systemd/user" "$BACKUP_DIR/services/user-units" 2>/dev/null || true
    fi

    # Custom system service files
    rm -rf "$BACKUP_DIR/services/system-units" 2>/dev/null || true
    if [[ -d "/etc/systemd/system" ]]; then
        mkdir -p "$BACKUP_DIR/services/system-units"
        sudo find /etc/systemd/system -maxdepth 1 -name "*.service" -exec cp {} "$BACKUP_DIR/services/system-units/" \; 2>/dev/null || true
        sudo chown -R "$USER:$USER" "$BACKUP_DIR/services/system-units" 2>/dev/null || true
    fi
}

capture_misc() {
    log_info "Capturing miscellaneous items..."

    # Installed fonts (user)
    if [[ -d "$HOME/.local/share/fonts" ]]; then
        ls "$HOME/.local/share/fonts" > "$BACKUP_DIR/configs/user/fonts-list.txt" 2>/dev/null || true
    fi

    # GTK themes/settings
    mkdir -p "$BACKUP_DIR/configs/user/.config"
    [[ -d "$HOME/.config/gtk-3.0" ]] && cp -a "$HOME/.config/gtk-3.0" "$BACKUP_DIR/configs/user/.config/" 2>/dev/null || true
    [[ -d "$HOME/.config/gtk-4.0" ]] && cp -a "$HOME/.config/gtk-4.0" "$BACKUP_DIR/configs/user/.config/" 2>/dev/null || true

    # dconf dump (GNOME/GTK settings)
    if command -v dconf &>/dev/null; then
        dconf dump / > "$BACKUP_DIR/configs/user/dconf-dump.txt" 2>/dev/null || true
    fi

    # Firewall rules
    if command -v ufw &>/dev/null; then
        sudo ufw status verbose > "$BACKUP_DIR/configs/system/ufw-status.txt" 2>/dev/null || true
        sudo chown "$USER:$USER" "$BACKUP_DIR/configs/system/ufw-status.txt" 2>/dev/null || true
    fi

    # Hostname and timezone
    cat /etc/hostname > "$BACKUP_DIR/configs/system/hostname.txt" 2>/dev/null || true
    timedatectl show > "$BACKUP_DIR/configs/system/timezone.txt" 2>/dev/null || true

    # Locale
    locale > "$BACKUP_DIR/configs/system/locale-current.txt" 2>/dev/null || true
}

generate_manifest() {
    log_info "Generating manifest..."

    cat > "$BACKUP_DIR/MANIFEST.md" << EOF
# System State Backup Manifest

**Last Updated:** $(date)
**Hostname:** $(hostname)
**User:** $USER
**Kernel:** $(uname -r)

## Packages

- Official: $(wc -l < "$BACKUP_DIR/packages/official.txt") packages
- AUR: $(wc -l < "$BACKUP_DIR/packages/aur.txt") packages
- Total explicit: $(wc -l < "$BACKUP_DIR/packages/all-explicit.txt") packages

## Services Enabled

### System Services
\`\`\`
$(cat "$BACKUP_DIR/services/system-enabled.txt")
\`\`\`

### User Services
\`\`\`
$(cat "$BACKUP_DIR/services/user-enabled.txt")
\`\`\`

## Configs Captured

### User Configs
\`\`\`
$(cd "$BACKUP_DIR/configs/user" && find . -type f | sed 's|^./||' | head -50)
\`\`\`

### System Configs
\`\`\`
$(cd "$BACKUP_DIR/configs/system" && find . -type f 2>/dev/null | sed 's|^./||' | head -50)
\`\`\`

## Restoration

Run the restore script:
\`\`\`bash
./restore.sh
\`\`\`
EOF
    log_success "Manifest generated"
}

create_restore_script() {
    log_info "Generating restore script..."

    cat > "$BACKUP_DIR/restore.sh" << 'RESTORE_EOF'
#!/bin/bash
#
# System State Restore Script
# Restores system state from backup created by capture.sh
#

set -euo pipefail

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN="${DRY_RUN:-false}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    else
        "$@"
    fi
}

if [[ ! -f "$BACKUP_DIR/MANIFEST.md" ]]; then
    log_error "Invalid backup directory. MANIFEST.md not found."
    exit 1
fi

echo "========================================"
echo "  System State Restore"
echo "========================================"
echo ""
echo "Backup: $BACKUP_DIR"
echo "Dry run: $DRY_RUN"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 0

restore_packages() {
    log_info "Installing official packages..."
    if [[ -f "$BACKUP_DIR/packages/official.txt" ]]; then
        run_cmd sudo pacman -S --needed - < "$BACKUP_DIR/packages/official.txt" || log_warn "Some packages failed"
    fi

    log_info "Installing AUR packages..."
    if [[ -f "$BACKUP_DIR/packages/aur.txt" ]] && command -v yay &>/dev/null; then
        while read -r pkg; do
            run_cmd yay -S --needed --noconfirm "$pkg" || log_warn "Failed to install AUR package: $pkg"
        done < "$BACKUP_DIR/packages/aur.txt"
    elif [[ -f "$BACKUP_DIR/packages/aur.txt" ]]; then
        log_warn "yay not found. Install yay first, then run:"
        echo "  yay -S --needed \$(cat $BACKUP_DIR/packages/aur.txt | tr '\n' ' ')"
    fi
}

restore_user_configs() {
    log_info "Restoring user configurations..."

    if [[ -d "$BACKUP_DIR/configs/user" ]]; then
        cd "$BACKUP_DIR/configs/user"

        for item in .bashrc .bash_profile .profile; do
            [[ -f "$item" ]] && run_cmd cp -a "$item" "$HOME/"
        done

        if [[ -d ".config" ]]; then
            mkdir -p "$HOME/.config"
            for item in .config/*; do
                [[ -e "$item" ]] && run_cmd cp -a "$item" "$HOME/.config/"
            done
        fi

        if [[ -f ".ssh/config" ]]; then
            mkdir -p "$HOME/.ssh"
            run_cmd cp -a ".ssh/config" "$HOME/.ssh/"
            chmod 600 "$HOME/.ssh/config"
        fi

        cd - > /dev/null
    fi
    log_success "User configs restored"
}

restore_system_configs() {
    log_info "Restoring system configurations..."

    if [[ -d "$BACKUP_DIR/configs/system/etc" ]]; then
        log_warn "System configs require manual review. Found:"
        find "$BACKUP_DIR/configs/system/etc" -type f | head -20
        echo ""
        echo "To restore system configs manually:"
        echo "  sudo cp -a $BACKUP_DIR/configs/system/etc/* /etc/"
        echo ""
        echo "Review each file before copying!"
    fi
}

restore_services() {
    log_info "Enabling system services..."

    if [[ -f "$BACKUP_DIR/services/system-enabled.txt" ]]; then
        while read -r service; do
            [[ "$service" == *".target" ]] && continue
            [[ "$service" == "getty@"* ]] && continue
            [[ "$service" == "systemd-"* ]] && continue
            run_cmd sudo systemctl enable "$service" 2>/dev/null || log_warn "Could not enable $service"
        done < "$BACKUP_DIR/services/system-enabled.txt"
    fi

    log_info "Enabling user services..."
    if [[ -f "$BACKUP_DIR/services/user-enabled.txt" ]]; then
        while read -r service; do
            run_cmd systemctl --user enable "$service" 2>/dev/null || log_warn "Could not enable user service $service"
        done < "$BACKUP_DIR/services/user-enabled.txt"
    fi

    if [[ -d "$BACKUP_DIR/services/user-units" ]]; then
        mkdir -p "$HOME/.config/systemd/user"
        run_cmd cp -a "$BACKUP_DIR/services/user-units/"* "$HOME/.config/systemd/user/" 2>/dev/null || true
        systemctl --user daemon-reload
    fi

    if [[ -d "$BACKUP_DIR/services/system-units" ]]; then
        log_info "Custom system service files found in $BACKUP_DIR/services/system-units/"
        echo "Copy manually with: sudo cp $BACKUP_DIR/services/system-units/*.service /etc/systemd/system/"
    fi

    log_success "Services configured"
}

restore_dconf() {
    if [[ -f "$BACKUP_DIR/configs/user/dconf-dump.txt" ]] && command -v dconf &>/dev/null; then
        log_info "Restoring dconf settings..."
        read -p "Restore dconf (GNOME/GTK) settings? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            run_cmd dconf load / < "$BACKUP_DIR/configs/user/dconf-dump.txt"
        fi
    fi
}

echo ""
echo "What would you like to restore?"
echo "  1) Everything (recommended)"
echo "  2) Packages only"
echo "  3) User configs only"
echo "  4) Services only"
echo "  5) Exit"
echo ""
read -p "Choice [1-5]: " choice

case $choice in
    1)
        restore_packages
        restore_user_configs
        restore_system_configs
        restore_services
        restore_dconf
        ;;
    2) restore_packages ;;
    3) restore_user_configs ;;
    4) restore_services ;;
    5) exit 0 ;;
    *) log_error "Invalid choice" && exit 1 ;;
esac

echo ""
log_success "Restore complete!"
echo ""
echo "Next steps:"
echo "  1. Review and manually restore system configs from: $BACKUP_DIR/configs/system/"
echo "  2. Reboot to apply all changes"
echo "  3. Run 'systemctl --user daemon-reload' if user services aren't starting"
RESTORE_EOF

    chmod +x "$BACKUP_DIR/restore.sh"
    log_success "Restore script generated"
}

git_commit_and_push() {
    log_info "Committing changes to git..."

    cd "$BACKUP_DIR"

    # Add all changes
    git add -A

    # Check if there are changes to commit
    if git diff --cached --quiet; then
        log_info "No changes to commit"
        return 0
    fi

    # Generate commit message with summary of changes
    local pkg_count=$(wc -l < packages/all-explicit.txt)
    local commit_msg="System state backup - $(date '+%Y-%m-%d %H:%M')

Packages: $pkg_count total ($(wc -l < packages/official.txt) official, $(wc -l < packages/aur.txt) AUR)
Kernel: $(uname -r)
Hostname: $(hostname)"

    git commit -m "$commit_msg"
    log_success "Changes committed"

    if [[ "$PUSH_TO_GITHUB" == "true" ]]; then
        log_info "Pushing to GitHub..."
        if git push -u origin master 2>/dev/null || git push -u origin main 2>/dev/null; then
            log_success "Pushed to GitHub"
        else
            log_warn "Could not push to GitHub. You may need to set up the remote."
        fi
    fi
}

# Main
main() {
    echo "========================================"
    echo "  System State Capture Tool"
    echo "========================================"
    echo ""

    setup_backup_dir
    setup_github_repo
    capture_packages
    capture_user_configs
    capture_system_configs
    capture_services
    capture_misc
    generate_manifest
    create_restore_script
    git_commit_and_push

    echo ""
    echo "========================================"
    log_success "Backup complete!"
    echo "========================================"
    echo ""
    echo "Location: $BACKUP_DIR"
    if [[ "$PUSH_TO_GITHUB" == "true" ]]; then
        echo "GitHub:   https://github.com/$(gh api user -q .login 2>/dev/null || echo 'USER')/$GITHUB_REPO"
    fi
    echo ""

    # Show summary
    du -sh "$BACKUP_DIR" | awk '{print "Total size: " $1}'
}

main "$@"
