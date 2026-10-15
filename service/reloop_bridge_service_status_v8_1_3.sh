#!/bin/bash
set -u

LABEL="com.guy.reloopbridge"
UID_NUM="$(id -u)"
LOG_DIR="$HOME/Library/Logs/ReloopBridge"

echo "Reloop Bridge Service v8.1.3"
echo "----------------------------"

if /bin/launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
  echo "LaunchAgent: LOADED"
  /bin/launchctl print "gui/$UID_NUM/$LABEL" 2>/dev/null | /usr/bin/grep -E "state =|pid =|last exit code" | /usr/bin/head -n 10
else
  echo "LaunchAgent: NOT LOADED"
fi

echo
if /usr/sbin/ioreg -p IOUSB -l -w 0 2>/dev/null | /usr/bin/grep -Fq "Reloop Jockey 3 ME"; then
  echo "Controller: CONNECTED"
else
  echo "Controller: NOT CONNECTED"
fi

echo
if /usr/bin/pgrep -f "reloop_bridge_engine_v8_0_3" >/dev/null 2>&1; then
  echo "Bridge engine v8.0.4: RUNNING"
  /usr/bin/pgrep -fl "reloop_bridge_engine_v8_0_3"
else
  echo "Bridge engine v8.0.4: NOT RUNNING"
fi

echo
echo "Log storage:"
/usr/bin/du -sh "$LOG_DIR" 2>/dev/null || echo "  (no log directory yet)"
echo "  Session logs: $(/usr/bin/find "$LOG_DIR" -type f -name 'reloop_v8_*_session_*.log' 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

echo
echo "Recent v8.1.3 service log:"
/usr/bin/tail -n 12 "$LOG_DIR/reloop_v8_1_2_service.log" 2>/dev/null || true
