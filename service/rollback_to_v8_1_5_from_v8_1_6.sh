#!/bin/bash
set -euo pipefail

LABEL="com.guy.reloopbridge"
SPOTLIGHT_LABEL="com.guy.reloopbridge.spotlightguard"
MOTION_LABEL="com.guy.reloopbridge.reducemotionguard"
UID_NUM="$(/usr/bin/id -u)"

APP_DIR="$HOME/Library/Application Support/ReloopBridge"
BRIDGE_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
MOTION_PLIST="$HOME/Library/LaunchAgents/$MOTION_LABEL.plist"
MOTION_HELPER="$APP_DIR/reloop_reduce_motion_guard_v8_1_6"
PACKAGE_MARKER="$APP_DIR/package_version"
BRIDGE_SUPERVISOR="$APP_DIR/reloop_bridge_service_v8_1_5.sh"
INSTALLED_ENGINE="$APP_DIR/reloop_bridge_engine_v8_0_8"

fail() {
  echo "ERROR: $*" >&2
  return 1
}

if /usr/bin/pgrep -x Traktor >/dev/null 2>&1; then
  fail "Traktor is running. Close Traktor before rolling back v8.1.6."
fi

if [[ -f "$MOTION_PLIST" ]]; then
  echo "Stopping v8.1.6 Reduce Motion guard..."
  /bin/launchctl bootout "gui/$UID_NUM" "$MOTION_PLIST" >/dev/null 2>&1 || true
  /bin/sleep 2
fi

/bin/rm -f "$MOTION_PLIST" "$MOTION_HELPER" "$PACKAGE_MARKER"

[[ -f "$BRIDGE_PLIST" ]] || fail "v8.1.5 bridge LaunchAgent plist is missing."
[[ -x "$BRIDGE_SUPERVISOR" ]] || fail "v8.1.5 bridge supervisor is missing."
[[ -x "$INSTALLED_ENGINE" ]] || fail "v8.0.8 installed engine is missing."

if ! /bin/launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
  echo "Loading v8.1.5 bridge service..."
  /bin/launchctl bootstrap "gui/$UID_NUM" "$BRIDGE_PLIST"
  /bin/launchctl kickstart -k "gui/$UID_NUM/$LABEL"
  /bin/sleep 2
fi

/bin/launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1 || fail "v8.1.5 bridge LaunchAgent is not loaded."
/bin/launchctl print "system/$SPOTLIGHT_LABEL" >/dev/null 2>&1 || fail "v8.1.5 Spotlight guard is not loaded."

echo
echo "ROLLBACK COMPLETE"
echo "Service/package: v8.1.5"
echo "Engine: v8.0.8"
echo "Reduce Motion guard v8.1.6 removed."
echo "Spotlight guard v8.1.5 left in place."
echo
echo "Note: macOS may retain the old helper entry in Full Disk Access. It is harmless after the helper file is removed."
