#!/bin/bash
set -u

LABEL="com.guy.reloopbridge"
SPOTLIGHT_LABEL="com.guy.reloopbridge.spotlightguard"
MOTION_LABEL="com.guy.reloopbridge.reducemotionguard"
UID_NUM="$(/usr/bin/id -u)"
APP_DIR="$HOME/Library/Application Support/ReloopBridge"
LOG_DIR="$HOME/Library/Logs/ReloopBridge"
MOTION_HELPER="$APP_DIR/reloop_reduce_motion_guard_v8_1_6"
PACKAGE_MARKER="$APP_DIR/package_version"
ENGINE_NAME="reloop_bridge_engine_v8_0_8"

echo "Reloop Bridge Service/package v8.1.6"
echo "------------------------------------"

if [[ -f "$PACKAGE_MARKER" ]]; then
  echo "Installed package marker: $(/bin/cat "$PACKAGE_MARKER" 2>/dev/null || echo unknown)"
else
  echo "Installed package marker: MISSING"
fi

echo
if /bin/launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
  echo "Bridge LaunchAgent (v8.1.5 component): LOADED"
  /bin/launchctl print "gui/$UID_NUM/$LABEL" 2>/dev/null | /usr/bin/grep -E "state =|pid =|last exit code" | /usr/bin/head -n 10
else
  echo "Bridge LaunchAgent: NOT LOADED"
fi

echo
if /bin/launchctl print "system/$SPOTLIGHT_LABEL" >/dev/null 2>&1; then
  echo "Spotlight guard (v8.1.5 component): LOADED"
  /bin/launchctl print "system/$SPOTLIGHT_LABEL" 2>/dev/null | /usr/bin/grep -E "state =|pid =|last exit code" | /usr/bin/head -n 10
else
  echo "Spotlight guard: NOT LOADED"
fi

echo
if /bin/launchctl print "gui/$UID_NUM/$MOTION_LABEL" >/dev/null 2>&1; then
  echo "Reduce Motion guard v8.1.6: LOADED"
  /bin/launchctl print "gui/$UID_NUM/$MOTION_LABEL" 2>/dev/null | /usr/bin/grep -E "state =|pid =|last exit code" | /usr/bin/head -n 10
else
  echo "Reduce Motion guard v8.1.6: NOT LOADED"
fi

echo
if /usr/bin/pgrep -x Traktor >/dev/null 2>&1; then
  echo "Traktor: RUNNING"
else
  echo "Traktor: NOT RUNNING"
fi

echo
if [[ -x "$MOTION_HELPER" ]]; then
  echo "Effective Reduce Motion: $("$MOTION_HELPER" --state 2>/dev/null || echo unknown)"
else
  echo "Effective Reduce Motion: helper missing"
fi

echo
echo "Spotlight indexing:"
/usr/bin/mdutil -s / 2>&1

echo
if /usr/sbin/ioreg -p IOUSB -l -w 0 2>/dev/null | /usr/bin/grep -Fq "Reloop Jockey 3 ME"; then
  echo "Controller: CONNECTED"
else
  echo "Controller: NOT CONNECTED"
fi

echo
if /usr/bin/pgrep -h "$ENGINE_NAME" >/dev/null 2>&1; then
  echo "Bridge engine v8.0.8: RUNNING"
  /usr/bin/pgrep -hl "$ENGINE_NAME"
else
  echo "Bridge engine v8.0.8: NOT RUNNING"
fi

echo
echo "Recent Reduce Motion guard log:"
/usr/bin/tail -n 16 "$LOG_DIR/reduce_motion_guard_v8_1_6.log" 2>/dev/null || true

echo
echo "Recent bridge service log:"
/usr/bin/tail -n 12 "$LOG_DIR/reloop_v8_1_5_service.log" 2>/dev/null || true

echo
echo "Recent Spotlight guard log:"
/usr/bin/tail -n 12 "/Library/Logs/ReloopBridge/spotlight_guard_v8_1_5.log" 2>/dev/null || true
