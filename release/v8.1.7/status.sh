#!/bin/bash
set -u
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

UID_NUM="$(id -u)"
APP_SUPPORT="$HOME/Library/Application Support/ReloopBridge"
WATCH_EXE="$HOME/Applications/Reloop DJ WatchGuard.app/Contents/MacOS/ReloopDJWatchGuard"
ENGINE="$APP_SUPPORT/reloop_bridge_engine_v8_0_8"

echo "=== BRIDGE ==="
launchctl print "gui/$UID_NUM/com.guy.reloopbridge" 2>/dev/null |
  grep -E 'state =|pid =|runs =|last exit code' |
  head -n 8 || echo "NOT LOADED"

echo
echo "=== WATCHGUARD ==="
launchctl print "gui/$UID_NUM/com.guy.reloopbridge.watchguard" 2>/dev/null |
  grep -E 'state =|pid =|runs =|last exit code' |
  head -n 8 || echo "NOT LOADED"

if [[ -x "$WATCH_EXE" ]]; then
  "$WATCH_EXE" --status
fi

echo
echo "WatchGuard health:"
cat "$APP_SUPPORT/watchguard-health.txt" 2>/dev/null || true

echo
echo "=== SPOTLIGHT HELPER ==="
launchctl print "system/com.guy.reloopbridge.spotlightguard" 2>/dev/null |
  grep -E 'state =|pid =|runs =|last exit code' |
  head -n 8 || echo "NOT LOADED"

echo
echo "Spotlight current state:"
mdutil -s / 2>&1

echo
echo "=== OBSOLETE AUTOMATION JOBS ==="
for label in \
  com.guy.reloopbridge.reducemotionguard \
  com.guy.reloopbridge.watchguard.candidate \
  com.guy.reloopbridge.bridge; do
  if launchctl print "gui/$UID_NUM/$label" >/dev/null 2>&1; then
    echo "$label: UNEXPECTEDLY LOADED"
  else
    echo "$label: absent"
  fi
done

for label in \
  com.guy.reloopbridge.spotlight.eventguard.candidate \
  com.guy.reloopbridge.spotlight; do
  if launchctl print "system/$label" >/dev/null 2>&1; then
    echo "$label: UNEXPECTEDLY LOADED"
  else
    echo "$label: absent"
  fi
done

echo
echo "=== ENGINE ==="
shasum -a 256 "$ENGINE" 2>/dev/null || true
pgrep -fl reloop_bridge_engine_v8_0_8 ||
  echo "Engine not running (normal if controller is disconnected)"

echo
echo "=== IDLE RESOURCE SNAPSHOT ==="
ps -Ao pid,%cpu,%mem,etime,command |
  grep -E 'ReloopDJWatchGuard|reloop_spotlight_event_guard_v8_1_7' |
  grep -v grep || true

echo
echo "=== RECENT AUTOMATION LOGS ==="
tail -n 20 "$HOME/Library/Logs/ReloopBridge/watchguard_v8_1_7.log" 2>/dev/null || true
tail -n 20 "/Library/Logs/ReloopBridge/spotlight_event_guard_v8_1_7.log" 2>/dev/null || true
