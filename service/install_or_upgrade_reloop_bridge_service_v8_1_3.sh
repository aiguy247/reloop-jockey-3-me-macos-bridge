#!/bin/bash
set -euo pipefail

LABEL="com.guy.reloopbridge"
VERSION="8.1.3"
ENGINE_VERSION="8.0.4"
EXPECTED_SOURCE_SHA="344a9572c2ada2b3c4e2839f2a91a8416eddb5236eb06963e1b6c0d1b54b3398"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLED_SOURCE="$PACKAGE_ROOT/dev/reloop_jockey3_bridge_v8_0_4_master_play_flash_48k.m"

PROJECT_ROOT="$HOME/Documents/reloop-controller"
DEV_DIR="$PROJECT_ROOT/dev"
SERVICE_DIR="$PROJECT_ROOT/service"
DOCS_DIR="$PROJECT_ROOT/docs"
LOG_DIR="$HOME/Library/Logs/ReloopBridge"

APP_DIR="$HOME/Library/Application Support/ReloopBridge"
ENGINE="$APP_DIR/reloop_bridge_engine_v8_0_4"
SUPERVISOR="$APP_DIR/reloop_bridge_service_v8_1_3.sh"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST="$PLIST_DIR/$LABEL.plist"
UID_NUM="$(id -u)"
ENGINE_TMP="$APP_DIR/.reloop_bridge_engine_v8_0_4.$$"

cleanup() {
  /bin/rm -f "$ENGINE_TMP" 2>/dev/null || true
}
trap cleanup EXIT

echo "Reloop Jockey 3 ME Bridge Service v$VERSION installer/upgrader"
echo "Engine: v$ENGINE_VERSION"
echo "Audio path: qualified v8.0.2 path unchanged"
echo "MIDI addition: actual Tempo Master Beat Phase also flashes the matching Play/Pause LED"
echo

if [[ ! -f "$BUNDLED_SOURCE" ]]; then
  echo "ERROR: Bundled v8.0.4 source is missing:"
  echo "  $BUNDLED_SOURCE"
  exit 1
fi

ACTUAL_SHA="$(/usr/bin/shasum -a 256 "$BUNDLED_SOURCE" | /usr/bin/awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$EXPECTED_SOURCE_SHA" ]]; then
  echo "ERROR: Bundled source SHA-256 mismatch."
  echo "Expected: $EXPECTED_SOURCE_SHA"
  echo "Actual:   $ACTUAL_SHA"
  exit 1
fi

if /usr/bin/pgrep -f "reloop_jockey3_bridge_v8_0_4_master_play_flash_48k" >/dev/null 2>&1; then
  echo "ERROR: A manually started v8.0.4 source build is running."
  echo "Stop it with Control-C first."
  exit 1
fi

/bin/mkdir -p "$DEV_DIR" "$SERVICE_DIR" "$DOCS_DIR" "$LOG_DIR" "$APP_DIR" "$PLIST_DIR"

TARGET_SOURCE="$DEV_DIR/reloop_jockey3_bridge_v8_0_4_master_play_flash_48k.m"
if [[ -f "$TARGET_SOURCE" ]]; then
  EXISTING_SHA="$(/usr/bin/shasum -a 256 "$TARGET_SOURCE" | /usr/bin/awk '{print $1}')"
  if [[ "$EXISTING_SHA" != "$EXPECTED_SOURCE_SHA" ]]; then
    echo "ERROR: Existing v8.0.4 DEV source has a different SHA-256:"
    echo "  $TARGET_SOURCE"
    echo "Refusing to overwrite it."
    exit 1
  fi
else
  /bin/cp "$BUNDLED_SOURCE" "$TARGET_SOURCE"
fi

echo "Compiling v8.0.4 candidate before stopping the current service..."
/usr/bin/clang -fobjc-arc \
  -framework Foundation \
  -framework CoreAudio \
  -framework CoreMIDI \
  -framework IOKit \
  -framework IOUSBHost \
  "$TARGET_SOURCE" \
  -o "$ENGINE_TMP"
/bin/chmod 755 "$ENGINE_TMP"

echo "Compilation passed."
echo "Stopping previous bridge service if loaded..."
/bin/launchctl bootout "gui/$UID_NUM" "$PLIST" >/dev/null 2>&1 || true
/bin/sleep 1
/bin/mv "$ENGINE_TMP" "$ENGINE"

cat > "$SUPERVISOR" <<'SUPERVISOR_EOF'
#!/bin/bash
set -u

ENGINE="$HOME/Library/Application Support/ReloopBridge/reloop_bridge_engine_v8_0_4"
LOG_DIR="$HOME/Library/Logs/ReloopBridge"
SERVICE_LOG="$LOG_DIR/reloop_v8_1_3_service.log"
LAUNCHD_OUT="$LOG_DIR/reloop_v8_1_3_launchd.out"
LAUNCHD_ERR="$LOG_DIR/reloop_v8_1_3_launchd.err"
PRODUCT_NAME="Reloop Jockey 3 ME"

SESSION_RETENTION_DAYS=30
SERVICE_LOG_MAX_BYTES=1048576
SERVICE_LOG_GENERATIONS=3
HOUSEKEEPING_INTERVAL_SECONDS=3600

child_pid=""
last_housekeeping=0

stamp() { /bin/date "+%Y-%m-%d %H:%M:%S"; }

file_size() {
  /usr/bin/stat -f%z "$1" 2>/dev/null || echo 0
}

rotate_log() {
  local log="$1"
  local max_bytes="$2"
  local generations="$3"
  local size=0

  [[ -f "$log" ]] || return 0
  size="$(file_size "$log")"
  [[ "$size" =~ ^[0-9]+$ ]] || size=0
  (( size >= max_bytes )) || return 0

  local i
  /bin/rm -f "${log}.${generations}" 2>/dev/null || true
  for ((i=generations-1; i>=1; i--)); do
    if [[ -f "${log}.${i}" ]]; then
      /bin/mv "${log}.${i}" "${log}.$((i+1))"
    fi
  done
  /bin/mv "$log" "${log}.1"
  : > "$log"
}

housekeeping() {
  /bin/mkdir -p "$LOG_DIR"

  /usr/bin/find "$LOG_DIR" -type f -name 'reloop_v8_*_session_*.log' \
    -mtime +$SESSION_RETENTION_DAYS -delete 2>/dev/null || true

  rotate_log "$SERVICE_LOG" "$SERVICE_LOG_MAX_BYTES" "$SERVICE_LOG_GENERATIONS"
  rotate_log "$LAUNCHD_OUT" "$SERVICE_LOG_MAX_BYTES" "$SERVICE_LOG_GENERATIONS"
  rotate_log "$LAUNCHD_ERR" "$SERVICE_LOG_MAX_BYTES" "$SERVICE_LOG_GENERATIONS"

  last_housekeeping="$(/bin/date +%s)"
}

service_log() {
  /bin/mkdir -p "$LOG_DIR"
  echo "$(stamp) | $*" >> "$SERVICE_LOG"
}

device_present() {
  /usr/sbin/ioreg -p IOUSB -l -w 0 2>/dev/null | /usr/bin/grep -Fq "$PRODUCT_NAME"
}

stop_child() {
  if [[ -n "$child_pid" ]] && /bin/kill -0 "$child_pid" 2>/dev/null; then
    service_log "Stopping bridge engine PID $child_pid."
    /bin/kill -INT "$child_pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      /bin/kill -0 "$child_pid" 2>/dev/null || break
      /bin/sleep 1
    done
    if /bin/kill -0 "$child_pid" 2>/dev/null; then
      service_log "Engine did not stop after SIGINT; sending SIGTERM."
      /bin/kill -TERM "$child_pid" 2>/dev/null || true
    fi
    wait "$child_pid" 2>/dev/null || true
  fi
  child_pid=""
}

shutdown() {
  service_log "Service stopping."
  stop_child
  housekeeping
  exit 0
}

trap shutdown INT TERM HUP

/bin/mkdir -p "$LOG_DIR"
housekeeping
service_log "Reloop Bridge Service v8.1.3 started. Audio path remains v8.0.2-qualified; engine v8.0.4 adds Tempo Master trash + Play/Pause LED flashing."

rapid_failures=0
failure_window_start=0

while true; do
  now="$(/bin/date +%s)"
  if (( now - last_housekeeping >= HOUSEKEEPING_INTERVAL_SECONDS )); then
    housekeeping
  fi

  if ! device_present; then
    rapid_failures=0
    failure_window_start=0
    /bin/sleep 1
    continue
  fi

  session_stamp="$(/bin/date "+%Y%m%d-%H%M%S")"
  session_log="$LOG_DIR/reloop_v8_1_3_session_${session_stamp}.log"

  service_log "Controller detected. Starting v8.0.4 engine (v8.0.2 qualified audio path + Tempo Master trash/Play LED gate). Session log: $session_log"
  "$ENGINE" >> "$session_log" 2>&1 &
  child_pid=$!

  unplugged=0
  while /bin/kill -0 "$child_pid" 2>/dev/null; do
    now="$(/bin/date +%s)"
    if (( now - last_housekeeping >= HOUSEKEEPING_INTERVAL_SECONDS )); then
      housekeeping
    fi

    if ! device_present; then
      unplugged=1
      service_log "Controller unplugged. Requesting clean engine shutdown."
      /bin/kill -INT "$child_pid" 2>/dev/null || true
      break
    fi
    /bin/sleep 1
  done

  wait "$child_pid" 2>/dev/null
  exit_code=$?
  child_pid=""

  if [[ "$unplugged" -eq 1 ]]; then
    rapid_failures=0
    failure_window_start=0
    service_log "Engine stopped after controller removal."
    housekeeping
    while device_present; do /bin/sleep 1; done
    continue
  fi

  /bin/sleep 1
  if ! device_present; then
    rapid_failures=0
    failure_window_start=0
    service_log "Engine exited during controller removal (status $exit_code)."
    housekeeping
    continue
  fi

  now="$(/bin/date +%s)"
  if [[ "$failure_window_start" -eq 0 ]] || (( now - failure_window_start > 60 )); then
    failure_window_start=$now
    rapid_failures=1
  else
    rapid_failures=$((rapid_failures + 1))
  fi

  service_log "Engine exited while controller is still present (status $exit_code; rapid failure $rapid_failures/3)."

  if (( rapid_failures >= 3 )); then
    service_log "Three rapid failures. Waiting for a physical unplug/replug before trying again."
    housekeeping
    while device_present; do /bin/sleep 1; done
    rapid_failures=0
    failure_window_start=0
    continue
  fi

  /bin/sleep 3
done
SUPERVISOR_EOF
/bin/chmod 755 "$SUPERVISOR"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$SUPERVISOR</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>5</integer>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/reloop_v8_1_3_launchd.out</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/reloop_v8_1_3_launchd.err</string>
</dict>
</plist>
EOF

/usr/bin/plutil -lint "$PLIST"

for name in \
  "install_or_upgrade_reloop_bridge_service_v8_1_3.sh" \
  "reloop_bridge_service_status_v8_1_3.sh" \
  "uninstall_reloop_bridge_service_v8_1_3.sh"
do
  src="$SCRIPT_DIR/$name"
  dst="$SERVICE_DIR/$name"
  if [[ -f "$src" && "$src" != "$dst" ]]; then
    /bin/cp "$src" "$dst"
    /bin/chmod 755 "$dst"
  fi
done

if [[ -f "$PACKAGE_ROOT/docs/README_Reloop_Bridge_Service_v8_1_3.md" ]]; then
  /bin/cp "$PACKAGE_ROOT/docs/README_Reloop_Bridge_Service_v8_1_3.md" "$DOCS_DIR/"
fi

echo "Starting v8.1.3 LaunchAgent..."
/bin/launchctl bootstrap "gui/$UID_NUM" "$PLIST"
/bin/launchctl kickstart -k "gui/$UID_NUM/$LABEL"
/bin/sleep 2

echo
echo "INSTALL / UPGRADE COMPLETE"
echo "Engine: v8.0.4"
echo "Audio path: v8.0.2 qualified path unchanged"
echo "Tempo Master trash + Play/Pause LED gate: integrated"
echo
echo "Project: $PROJECT_ROOT"
echo "Runtime logs: $LOG_DIR"
echo
/bin/launchctl print "gui/$UID_NUM/$LABEL" 2>/dev/null | /usr/bin/grep -E "state =|pid =|last exit code" | /usr/bin/head -n 10 || true
