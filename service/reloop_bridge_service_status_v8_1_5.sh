#!/bin/bash
set -u

LABEL="com.guy.reloopbridge"
SPOTLIGHT_LABEL="com.guy.reloopbridge.spotlightguard"
UID_NUM="$(id -u)"
LOG_DIR="$HOME/Library/Logs/ReloopBridge"
ROOT_LOG="/Library/Logs/ReloopBridge/spotlight_guard_v8_1_5.log"
ENGINE_NAME="reloop_bridge_engine_v8_0_8"

echo "Reloop Bridge Service v8.1.5"
echo "----------------------------"

if /bin/launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
  echo "Bridge LaunchAgent: LOADED"
  /bin/launchctl print "gui/$UID_NUM/$LABEL" 2>/dev/null |
    /usr/bin/grep -E "state =|pid =|last exit code" |
    /usr/bin/head -n 10
else
  echo "Bridge LaunchAgent: NOT LOADED"
fi

echo
if /bin/launchctl print "system/$SPOTLIGHT_LABEL" >/dev/null 2>&1; then
  echo "Spotlight guard LaunchDaemon: LOADED"
  /bin/launchctl print "system/$SPOTLIGHT_LABEL" 2>/dev/null |
    /usr/bin/grep -E "state =|pid =|last exit code" |
    /usr/bin/head -n 10
else
  echo "Spotlight guard LaunchDaemon: NOT LOADED"
fi

echo
if /usr/bin/pgrep -x Traktor >/dev/null 2>&1; then
  echo "Traktor: RUNNING"
else
  echo "Traktor: NOT RUNNING"
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
if /usr/bin/pgrep -f "$ENGINE_NAME" >/dev/null 2>&1; then
  echo "Bridge engine v8.0.8: RUNNING"
  /usr/bin/pgrep -fl "$ENGINE_NAME"
else
  echo "Bridge engine v8.0.8: NOT RUNNING"
fi

echo
echo "Recent v8.1.5 service log:"
/usr/bin/tail -n 12 "$LOG_DIR/reloop_v8_1_5_service.log" 2>/dev/null || true

echo
echo "Recent Spotlight guard log:"
/usr/bin/tail -n 12 "$ROOT_LOG" 2>/dev/null || true
