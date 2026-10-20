#!/bin/bash
set -eEuo pipefail

LABEL="com.guy.reloopbridge"
SPOTLIGHT_LABEL="com.guy.reloopbridge.spotlightguard"
VERSION="8.1.5"
ENGINE_VERSION="8.0.8"
EXPECTED_SOURCE_SHA="4fed39df7a9b2a792ceca42c68bf8d5c278e96505717888998411563b6e00537"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXPECTED_BRANCH="phase4-diagnostics"
SOURCE="$REPO_ROOT/src/phase4/reloop_jockey3_bridge_v8_0_8_phase4_recovery_diagnostics_48k.m"
BUILD_SCRIPT="$REPO_ROOT/tools/phase4/build_diagnostic_v8_0_8.sh"
BUILT_ENGINE="$REPO_ROOT/build/reloop_bridge_engine_v8_0_8_phase4_recovery_diagnostics"
GUARD_SOURCE="$SCRIPT_DIR/reloop_spotlight_guard_v8_1_5.sh"

APP_DIR="$HOME/Library/Application Support/ReloopBridge"
ENGINE="$APP_DIR/reloop_bridge_engine_v8_0_8"
SUPERVISOR="$APP_DIR/reloop_bridge_service_v8_1_5.sh"
LOG_DIR="$HOME/Library/Logs/ReloopBridge"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST="$PLIST_DIR/$LABEL.plist"
UID_NUM="$(id -u)"

ROLLBACK_DIR="$APP_DIR/rollback_v8_1_3"
ROLLBACK_PLIST="$ROLLBACK_DIR/$LABEL.plist"
ROLLBACK_ENGINE="$ROLLBACK_DIR/reloop_bridge_engine_v8_0_4"
ROLLBACK_SUPERVISOR="$ROLLBACK_DIR/reloop_bridge_service_v8_1_3.sh"
ROLLBACK_LOADED_MARKER="$ROLLBACK_DIR/was_loaded"

ROOT_APP_DIR="/Library/Application Support/ReloopBridge"
ROOT_GUARD="$ROOT_APP_DIR/reloop_spotlight_guard_v8_1_5.sh"
ROOT_PLIST="/Library/LaunchDaemons/$SPOTLIGHT_LABEL.plist"
ROOT_LOG_DIR="/Library/Logs/ReloopBridge"

TMP_DIR=""
LEGACY_WAS_LOADED=0
GUARD_INSTALLED=0
SERVICE_REPLACED=0
SUCCESS=0

fail() {
  echo "ERROR: $*" >&2
  return 1
}

cleanup_tmp() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    /bin/rm -rf "$TMP_DIR"
  fi
}

rollback_on_error() {
  trap - ERR
  set +e

  echo
  echo "v8.1.5 installation did not complete. Rolling back local service changes..."

  if [[ "$SERVICE_REPLACED" -eq 1 ]]; then
    /bin/launchctl bootout "gui/$UID_NUM" "$PLIST" >/dev/null 2>&1 || true

    if [[ -f "$ROLLBACK_PLIST" ]]; then
      /bin/cp "$ROLLBACK_PLIST" "$PLIST"
      /bin/chmod 644 "$PLIST"
    fi
    if [[ -f "$ROLLBACK_ENGINE" ]]; then
      /bin/cp "$ROLLBACK_ENGINE" "$APP_DIR/reloop_bridge_engine_v8_0_4"
      /bin/chmod 755 "$APP_DIR/reloop_bridge_engine_v8_0_4"
    fi
    if [[ -f "$ROLLBACK_SUPERVISOR" ]]; then
      /bin/cp "$ROLLBACK_SUPERVISOR" "$APP_DIR/reloop_bridge_service_v8_1_3.sh"
      /bin/chmod 755 "$APP_DIR/reloop_bridge_service_v8_1_3.sh"
    fi

    if [[ "$LEGACY_WAS_LOADED" -eq 1 && -f "$PLIST" ]]; then
      /bin/launchctl bootstrap "gui/$UID_NUM" "$PLIST" >/dev/null 2>&1 || true
      /bin/launchctl kickstart -k "gui/$UID_NUM/$LABEL" >/dev/null 2>&1 || true
    fi
  fi

  if [[ "$GUARD_INSTALLED" -eq 1 ]]; then
    /usr/bin/sudo /bin/launchctl bootout system "$ROOT_PLIST" >/dev/null 2>&1 || true
    /bin/sleep 2
    /usr/bin/sudo /bin/rm -f "$ROOT_PLIST" "$ROOT_GUARD" >/dev/null 2>&1 || true
  fi

  cleanup_tmp
  echo "Rollback attempt finished. Qualified v8.1.3 files were preserved."
}

signal_abort() {
  echo
  echo "Installation interrupted."
  return 130
}

trap rollback_on_error ERR
trap signal_abort INT TERM HUP

[[ -d "$REPO_ROOT/.git" ]] || fail "This installer must be run from the permanent Git repository."
CURRENT_BRANCH="$(/usr/bin/git -C "$REPO_ROOT" branch --show-current)"
[[ "$CURRENT_BRANCH" == "$EXPECTED_BRANCH" ]] || fail "Expected Git branch $EXPECTED_BRANCH; found $CURRENT_BRANCH."
[[ -z "$(/usr/bin/git -C "$REPO_ROOT" status --porcelain)" ]] || fail "Repository has uncommitted changes."
[[ -f "$SOURCE" ]] || fail "Missing v8.0.8 source: $SOURCE"
[[ -f "$BUILD_SCRIPT" ]] || fail "Missing v8.0.8 build script: $BUILD_SCRIPT"
[[ -f "$GUARD_SOURCE" ]] || fail "Missing Spotlight guard: $GUARD_SOURCE"

if /usr/bin/pgrep -f "$BUILT_ENGINE" >/dev/null 2>&1; then
  fail "A foreground v8.0.8 candidate is running from the repository build path. Stop it with Control-C before installing v8.1.5."
fi

/bin/bash -n "$GUARD_SOURCE"
SOURCE_SHA="$(/usr/bin/shasum -a 256 "$SOURCE" | /usr/bin/awk '{print $1}')"
[[ "$SOURCE_SHA" == "$EXPECTED_SOURCE_SHA" ]] || fail "v8.0.8 source checksum mismatch."

echo "Building and validating engine v$ENGINE_VERSION before changing the installed service..."
/bin/bash "$BUILD_SCRIPT"
[[ -x "$BUILT_ENGINE" ]] || fail "v8.0.8 build output is missing."

/bin/mkdir -p "$APP_DIR" "$LOG_DIR" "$PLIST_DIR" "$ROLLBACK_DIR"

if /bin/launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
  LEGACY_WAS_LOADED=1
fi

# Preserve the current v8.1.3 runtime exactly once. Re-running this installer
# must never replace the rollback copy with v8.1.5 files.
if [[ ! -f "$ROLLBACK_PLIST" && -f "$PLIST" ]]; then
  /bin/cp -p "$PLIST" "$ROLLBACK_PLIST"
fi
if [[ ! -f "$ROLLBACK_ENGINE" && -f "$APP_DIR/reloop_bridge_engine_v8_0_4" ]]; then
  /bin/cp -p "$APP_DIR/reloop_bridge_engine_v8_0_4" "$ROLLBACK_ENGINE"
fi
if [[ ! -f "$ROLLBACK_SUPERVISOR" && -f "$APP_DIR/reloop_bridge_service_v8_1_3.sh" ]]; then
  /bin/cp -p "$APP_DIR/reloop_bridge_service_v8_1_3.sh" "$ROLLBACK_SUPERVISOR"
fi
if [[ "$LEGACY_WAS_LOADED" -eq 1 ]]; then
  : > "$ROLLBACK_LOADED_MARKER"
fi

[[ -f "$ROLLBACK_PLIST" ]] || fail "Could not preserve the current v8.1.3 LaunchAgent for rollback."
[[ -f "$ROLLBACK_ENGINE" ]] || fail "Could not preserve the current v8.0.4 engine for rollback."
[[ -f "$ROLLBACK_SUPERVISOR" ]] || fail "Could not preserve the current v8.1.3 supervisor for rollback."

TMP_DIR="$(/usr/bin/mktemp -d)"
USER_PLIST_TMP="$TMP_DIR/$LABEL.plist"
ROOT_PLIST_TMP="$TMP_DIR/$SPOTLIGHT_LABEL.plist"
SUPERVISOR_TMP="$TMP_DIR/reloop_bridge_service_v8_1_5.sh"

/bin/cat > "$SUPERVISOR_TMP" <<'SUPERVISOR_EOF'
#!/bin/bash
set -u

ENGINE="$HOME/Library/Application Support/ReloopBridge/reloop_bridge_engine_v8_0_8"
LOG_DIR="$HOME/Library/Logs/ReloopBridge"
SERVICE_LOG="$LOG_DIR/reloop_v8_1_5_service.log"
LAUNCHD_OUT="$LOG_DIR/reloop_v8_1_5_launchd.out"
LAUNCHD_ERR="$LOG_DIR/reloop_v8_1_5_launchd.err"
PRODUCT_NAME="Reloop Jockey 3 ME"

SESSION_RETENTION_DAYS=30
SERVICE_LOG_MAX_BYTES=1048576
SERVICE_LOG_GENERATIONS=3
HOUSEKEEPING_INTERVAL_SECONDS=3600

child_pid=""
last_housekeeping=0
shutdown_requested=0

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
  /bin/rm -f "$log.$generations" 2>/dev/null || true
  for ((i=generations-1; i>=1; i--)); do
    if [[ -f "$log.$i" ]]; then
      /bin/mv "$log.$i" "$log.$((i+1))"
    fi
  done
  /bin/mv "$log" "$log.1"
  : > "$log"
}

housekeeping() {
  /bin/mkdir -p "$LOG_DIR"

  /usr/bin/find "$LOG_DIR" -type f -name 'reloop_v8_*_session_*.log'     -mtime +$SESSION_RETENTION_DAYS -delete 2>/dev/null || true

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

request_shutdown() {
  shutdown_requested=1
  service_log "Service stopping."
  stop_child
  housekeeping
}

trap request_shutdown INT TERM HUP

/bin/mkdir -p "$LOG_DIR"
housekeeping
service_log "Reloop Bridge Service v8.1.5 started. Engine v8.0.8 Phase 4 recovery diagnostics; audio/MIDI routing remains derived from the qualified v8.0.4 baseline."

rapid_failures=0
failure_window_start=0

while [[ "$shutdown_requested" -eq 0 ]]; do
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
  session_log="$LOG_DIR/reloop_v8_1_5_session_$session_stamp.log"

  service_log "Controller detected. Starting v8.0.8 engine. Session log: $session_log"
  "$ENGINE" >> "$session_log" 2>&1 &
  child_pid=$!

  unplugged=0
  while [[ "$shutdown_requested" -eq 0 ]] && /bin/kill -0 "$child_pid" 2>/dev/null; do
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

  if [[ "$shutdown_requested" -eq 1 ]]; then
    stop_child
    break
  fi

  wait "$child_pid" 2>/dev/null
  child_status=$?
  child_pid=""

  if [[ "$unplugged" -eq 1 ]]; then
    rapid_failures=0
    failure_window_start=0
    service_log "Engine stopped after controller removal."
    housekeeping
    while [[ "$shutdown_requested" -eq 0 ]] && device_present; do /bin/sleep 1; done
    continue
  fi

  /bin/sleep 1
  if ! device_present; then
    rapid_failures=0
    failure_window_start=0
    service_log "Engine ended during controller removal (status $child_status)."
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

  service_log "Engine ended while controller is still present (status $child_status; rapid failure $rapid_failures/3)."

  if (( rapid_failures >= 3 )); then
    service_log "Three rapid failures. Waiting for a physical unplug/replug before trying again."
    housekeeping
    while [[ "$shutdown_requested" -eq 0 ]] && device_present; do /bin/sleep 1; done
    rapid_failures=0
    failure_window_start=0
    continue
  fi

  /bin/sleep 3
done

housekeeping
service_log "Reloop Bridge Service v8.1.5 stopped."
SUPERVISOR_EOF

/bin/chmod 755 "$SUPERVISOR_TMP"
/bin/bash -n "$SUPERVISOR_TMP"

/bin/cat > "$USER_PLIST_TMP" <<EOF
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
  <string>$LOG_DIR/reloop_v8_1_5_launchd.out</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/reloop_v8_1_5_launchd.err</string>
</dict>
</plist>
EOF

/bin/cat > "$ROOT_PLIST_TMP" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$SPOTLIGHT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$ROOT_GUARD</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>5</integer>
  <key>StandardOutPath</key>
  <string>$ROOT_LOG_DIR/spotlight_guard_v8_1_5_launchd.out</string>
  <key>StandardErrorPath</key>
  <string>$ROOT_LOG_DIR/spotlight_guard_v8_1_5_launchd.err</string>
</dict>
</plist>
EOF

/usr/bin/plutil -lint "$USER_PLIST_TMP"
/usr/bin/plutil -lint "$ROOT_PLIST_TMP"

echo
echo "Administrator approval is required once to install the root Spotlight guard."
/usr/bin/sudo -v

/usr/bin/sudo /bin/mkdir -p "$ROOT_APP_DIR" "$ROOT_LOG_DIR"
/usr/bin/sudo /usr/bin/install -o root -g wheel -m 755 "$GUARD_SOURCE" "$ROOT_GUARD"
/usr/bin/sudo /usr/bin/install -o root -g wheel -m 644 "$ROOT_PLIST_TMP" "$ROOT_PLIST"
GUARD_INSTALLED=1
/usr/bin/sudo /bin/launchctl bootout system "$ROOT_PLIST" >/dev/null 2>&1 || true
/usr/bin/sudo /bin/launchctl bootstrap system "$ROOT_PLIST"
/usr/bin/sudo /bin/launchctl kickstart -k "system/$SPOTLIGHT_LABEL"

/usr/bin/sudo /bin/launchctl print "system/$SPOTLIGHT_LABEL" >/dev/null 2>&1 || fail "Spotlight guard LaunchDaemon did not load."

echo "Stopping current bridge service..."
/bin/launchctl bootout "gui/$UID_NUM" "$PLIST" >/dev/null 2>&1 || true
SERVICE_REPLACED=1

/bin/cp "$BUILT_ENGINE" "$ENGINE"
/bin/chmod 755 "$ENGINE"
/bin/cp "$SUPERVISOR_TMP" "$SUPERVISOR"
/bin/chmod 755 "$SUPERVISOR"
/bin/cp "$USER_PLIST_TMP" "$PLIST"
/bin/chmod 644 "$PLIST"

/bin/launchctl bootstrap "gui/$UID_NUM" "$PLIST"
/bin/launchctl kickstart -k "gui/$UID_NUM/$LABEL"
/bin/sleep 2

/bin/launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1 || fail "v8.1.5 bridge LaunchAgent did not load."

SUCCESS=1
trap - ERR
cleanup_tmp

echo
echo "INSTALLATION PASSED"
echo "Service/package: v8.1.5"
echo "Engine: v8.0.8"
echo "Login service: $LABEL"
echo "Spotlight guard: $SPOTLIGHT_LABEL"
echo "Rollback copy: $ROLLBACK_DIR"
echo
echo "Spotlight indexing status:"
/usr/bin/mdutil -s /
echo
/bin/launchctl print "gui/$UID_NUM/$LABEL" 2>/dev/null | /usr/bin/grep -E "state =|pid =|last exit code" | /usr/bin/head -n 10 || true
echo
/usr/bin/sudo /bin/launchctl print "system/$SPOTLIGHT_LABEL" 2>/dev/null | /usr/bin/grep -E "state =|pid =|last exit code" | /usr/bin/head -n 10 || true
