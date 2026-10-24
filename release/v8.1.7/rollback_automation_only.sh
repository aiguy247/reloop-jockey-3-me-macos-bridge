#!/bin/bash
set -eEuo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

UID_NUM="$(id -u)"
APP_SUPPORT="$HOME/Library/Application Support/ReloopBridge"
WATCH_LABEL="com.guy.reloopbridge.watchguard"
SPOT_LABEL="com.guy.reloopbridge.spotlightguard"
WATCH_PLIST="$HOME/Library/LaunchAgents/$WATCH_LABEL.plist"
WATCH_APP="$HOME/Applications/Reloop DJ WatchGuard.app"
SPOT_PLIST="/Library/LaunchDaemons/$SPOT_LABEL.plist"
SPOT_EXE="/Library/Application Support/ReloopBridge/reloop_spotlight_event_guard_v8_1_7"
ROOT_STATE="/var/db/com.guy.reloopbridge/spotlight-pre-traktor-state.txt"
USER_STATE="$APP_SUPPORT/watchguard-user-state.plist"
SOCKET_PATH="/var/run/com.guy.reloopbridge.spotlight.sock"

[[ -z "$(pgrep -x Traktor 2>/dev/null || true)" ]] || {
  echo "ERROR: Close Traktor before removing automation." >&2
  exit 1
}

echo "Reconciling saved states before removing automation..."

# Restart WatchGuard in its FDA-approved launchd context while Traktor is closed.
launchctl kickstart -k "gui/$UID_NUM/$WATCH_LABEL" >/dev/null 2>&1 || true
sleep 2

if [[ -f "$USER_STATE" ]]; then
  echo "ERROR: Reduce Motion recovery state still exists. Automation was NOT removed." >&2
  exit 1
fi

if sudo test -f "$ROOT_STATE"; then
  echo "ERROR: Spotlight recovery state still exists. Automation was NOT removed." >&2
  exit 1
fi

launchctl bootout "gui/$UID_NUM/$WATCH_LABEL" >/dev/null 2>&1 || true
[[ -f "$WATCH_PLIST" ]] &&
  launchctl bootout "gui/$UID_NUM" "$WATCH_PLIST" >/dev/null 2>&1 || true

sudo launchctl bootout "system/$SPOT_LABEL" >/dev/null 2>&1 || true
[[ -f "$SPOT_PLIST" ]] &&
  sudo launchctl bootout system "$SPOT_PLIST" >/dev/null 2>&1 || true

rm -f "$WATCH_PLIST"
rm -rf "$WATCH_APP"

sudo rm -f "$SPOT_PLIST" "$SPOT_EXE" "$SOCKET_PATH"

echo "Event-driven Spotlight/Reduce Motion automation removed."
echo "Qualified bridge com.guy.reloopbridge was left installed and untouched."
