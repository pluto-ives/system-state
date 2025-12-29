# System State Tool - Progress

## Completed

### Phase 1: Core Capture Tool
- Created `capture.sh` - main script that captures:
  - Official pacman packages
  - AUR packages via yay
  - User dotfiles and configs
  - System configs (requires sudo)
  - Enabled systemd services (system and user)
  - Custom systemd unit files
  - dconf/GTK settings
  - UFW firewall status

### Phase 2: Restore Script
- Embedded `restore.sh` in backup output
- Interactive menu for selective restore
- Dry-run mode support (`DRY_RUN=true`)
- Handles packages, configs, and services

### Phase 3: Git & GitHub Integration
- Auto-initializes git repo in backup directory
- Creates private GitHub repo via `gh` CLI
- Commits with descriptive messages including package counts
- Auto-pushes to GitHub after each backup

### Phase 4: Weekly Reminder Timer
- Created `prompt-backup.sh` - opens terminal with backup prompt
- Created systemd user timer (`system-state-backup.timer`)
- Runs every Sunday at 10:00 AM
- Persistent (catches up if missed)
- Enabled and active

## Files Created

```
~/Projects/system-state/
  capture.sh          # Main capture script (run with sudo)
  prompt-backup.sh    # Terminal prompt for weekly reminder
  docs/
    PROGRESS.md       # This file

~/.config/systemd/user/
  system-state-backup.service   # Service that runs prompt
  system-state-backup.timer     # Weekly timer (Sunday 10AM)

~/system-state-backup/          # Created on first run
  .git/                         # Git repo
  packages/                     # Package lists
  configs/user/                 # User dotfiles
  configs/system/               # System configs
  services/                     # Systemd services
  restore.sh                    # Restore script
  MANIFEST.md                   # Human-readable summary
```

## Usage

### Manual Backup (Full)
```bash
sudo ~/Projects/system-state/capture.sh
```

### Check Timer Status
```bash
systemctl --user list-timers system-state-backup.timer
```

### Trigger Reminder Manually
```bash
systemctl --user start system-state-backup.service
```

### View Backup History
```bash
cd ~/system-state-backup && git log --oneline
```

### Environment Variables
- `SYSTEM_STATE_BACKUP_DIR` - Custom backup location (default: ~/system-state-backup)
- `SYSTEM_STATE_GITHUB_REPO` - GitHub repo name (default: system-state-backup)
- `PUSH_TO_GITHUB` - Set to "false" to disable GitHub push

## Restore on Fresh Install

1. Install base Arch Linux
2. Install yay (for AUR)
3. Clone your backup: `gh repo clone system-state-backup`
4. Run restore: `./restore.sh`
