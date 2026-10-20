#!/bin/bash
set -euo pipefail

LABEL="com.guy.reloopbridge"
SPOTLIGHT_LABEL="com.guy.reloopbridge.spotlightguard"
UID_NUM="$(id -u)"

APP_DIR="$HOME/Library/Application Support/ReloopBridge"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
ROLLBACK_DIR="$APP_DIR/rollback_v8_1_3"
ROLLBACK_PLIST="$ROLLBACK_DIR/$LABEL.plist"
ROLLBACK_ENGINE="$ROLLBACK_DIR/reloop_bridge_engine_v8_0_4"
ROLLBACK_SUPERVISOR="$ROLLBACK_DIR/reloop_bridge_service_v8_1_3.sh"

ROOT_GUARD="/Library/Application Support/ReloopBridge/reloop_spotlight_guard_v8_1_5.sh"
ROOT_PLIST="/Library/LaunchDaemons/$SPOTLIGHT_LABEL.plist"

fail() {
  echo "ERROR: $*" >&2
  return 1
}

[[ -f "$ROLLBACK_PLIST" ]] || fail "Rollback LaunchAgent copy is missing."
[[ -f "$ROLLBACK_ENGINE" ]] || fail "Rollback v8.0.4 engine copy is missing."
[[ -f "$ROLLBACK_SUPERVISOR" ]] || fail "Rollback v8.1.3 supervisor copy is missing."

echo "Administrator approval is required to remove the v8.1.5 Spotlight guard."
/usr/bin/sudo -v

/bin/launchctl bootout "gui/$UID_NUM" "$PLIST" >/dev/null 2>&1 || true

/usr/bin/sudo /bin/launchctl bootout system "$ROOT_PLIST" >/dev/null 2>&1 || true
/bin/sleep 2
/usr/bin/sudo /bin/rm -f "$ROOT_PLIST" "$ROOT_GUARD"

# Restore the exact files preserved before v8.1.5 installation.
/bin/cp "$ROLLBACK_ENGINE" "$APP_DIR/reloop_bridge_engine_v8_0_4"
/bin/chmod 755 "$APP_DIR/reloop_bridge_engine_v8_0_4"
/bin/cp "$ROLLBACK_SUPERVISOR" "$APP_DIR/reloop_bridge_service_v8_1_3.sh"
/bin/chmod 755 "$APP_DIR/reloop_bridge_service_v8_1_3.sh"
/bin/cp "$ROLLBACK_PLIST" "$PLIST"
/bin/chmod 644 "$PLIST"

/usr/bin/plutil -lint "$PLIST"
/bin/launchctl bootstrap "gui/$UID_NUM" "$PLIST"
/bin/launchctl kickstart -k "gui/$UID_NUM/$LABEL"
/bin/sleep 2

echo
echo "ROLLBACK COMPLETE"
echo "Qualified v8.1.3 LaunchAgent restored."
echo "Spotlight indexing status:"
/usr/bin/mdutil -s /
echo
/bin/launchctl print "gui/$UID_NUM/$LABEL" 2>/dev/null |
  /usr/bin/grep -E "state =|pid =|last exit code" |
  /usr/bin/head -n 10 || true
