#!/bin/bash
set -euo pipefail

LABEL="com.guy.reloopbridge"
APP_DIR="$HOME/Library/Application Support/ReloopBridge"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

/bin/launchctl bootout "gui/$UID_NUM" "$PLIST" >/dev/null 2>&1 || true
/bin/rm -f "$PLIST"
/bin/rm -rf "$APP_DIR"

echo "Reloop Bridge Service uninstalled."
echo "Project files under ~/Documents/reloop-controller were preserved."
echo "Logs under ~/Library/Logs/ReloopBridge were preserved."
