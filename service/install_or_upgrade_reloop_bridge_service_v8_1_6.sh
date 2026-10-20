#!/bin/bash
set -eEuo pipefail

PACKAGE_VERSION="8.1.6"
ENGINE_VERSION="8.0.8"
BRIDGE_COMPONENT_VERSION="8.1.5"
LABEL="com.guy.reloopbridge"
SPOTLIGHT_LABEL="com.guy.reloopbridge.spotlightguard"
MOTION_LABEL="com.guy.reloopbridge.reducemotionguard"
EXPECTED_SOURCE_SHA="4fed39df7a9b2a792ceca42c68bf8d5c278e96505717888998411563b6e00537"
EXPECTED_ENGINE_SHA="66355176b2bc4193e4a749c72a56ab48771b71ed91d1cb8f638fd924961618a4"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO="$HOME/Documents/A-GuyCodeProjects/Traktor-dev/reloop-jockey-3-me-macos-bridge"
SOURCE="$REPO/src/phase4/reloop_jockey3_bridge_v8_0_8_phase4_recovery_diagnostics_48k.m"
BUILD_SCRIPT="$REPO/tools/phase4/build_diagnostic_v8_0_8.sh"
BUILT_ENGINE="$REPO/build/reloop_bridge_engine_v8_0_8_phase4_recovery_diagnostics"
MOTION_SOURCE="$SCRIPT_DIR/reloop_reduce_motion_guard_v8_1_6.m"

APP_DIR="$HOME/Library/Application Support/ReloopBridge"
LOG_DIR="$HOME/Library/Logs/ReloopBridge"
PLIST_DIR="$HOME/Library/LaunchAgents"
BRIDGE_PLIST="$PLIST_DIR/$LABEL.plist"
MOTION_PLIST="$PLIST_DIR/$MOTION_LABEL.plist"
MOTION_HELPER="$APP_DIR/reloop_reduce_motion_guard_v8_1_6"
PACKAGE_MARKER="$APP_DIR/package_version"
UID_NUM="$(/usr/bin/id -u)"

BRIDGE_SUPERVISOR="$APP_DIR/reloop_bridge_service_v8_1_5.sh"
INSTALLED_ENGINE="$APP_DIR/reloop_bridge_engine_v8_0_8"
ROOT_SPOTLIGHT_PLIST="/Library/LaunchDaemons/$SPOTLIGHT_LABEL.plist"
ROOT_SPOTLIGHT_GUARD="/Library/Application Support/ReloopBridge/reloop_spotlight_guard_v8_1_5.sh"

CANDIDATE_DIR="$APP_DIR/test-v8.1.6"

TMP_DIR=""
MOTION_AGENT_LOADED=0
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

motion_state() {
  if [[ -x "$MOTION_HELPER" ]]; then
    "$MOTION_HELPER" --state 2>/dev/null || echo unknown
  else
    echo unavailable
  fi
}

stop_pid_file() {
  local file="$1"
  local description="$2"
  [[ -f "$file" ]] || return 0

  local pid
  pid="$(/bin/cat "$file" 2>/dev/null || true)"
  if [[ "$pid" =~ ^[0-9]+$ ]] && /bin/kill -0 "$pid" 2>/dev/null; then
    echo "Stopping $description PID $pid..."
    /bin/kill -TERM "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      /bin/kill -0 "$pid" 2>/dev/null || break
      /bin/sleep 1
    done
    if /bin/kill -0 "$pid" 2>/dev/null; then
      fail "$description did not stop cleanly."
    fi
  fi
  /bin/rm -f "$file"
}

stop_test_candidates() {
  local version
  for version in 5 4 3 2; do
    stop_pid_file "$CANDIDATE_DIR/motion_guard_v${version}.pid" "v8.1.6 candidate v$version Reduce Motion helper"
    stop_pid_file "$CANDIDATE_DIR/supervisor_v${version}.pid" "v8.1.6 candidate v$version bridge"
  done
}

ensure_bridge_loaded() {
  if /bin/launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
    return 0
  fi

  [[ -f "$BRIDGE_PLIST" ]] || fail "Existing v8.1.5 bridge LaunchAgent plist is missing: $BRIDGE_PLIST"
  [[ -x "$BRIDGE_SUPERVISOR" ]] || fail "Existing v8.1.5 bridge supervisor is missing: $BRIDGE_SUPERVISOR"
  [[ -x "$INSTALLED_ENGINE" ]] || fail "Installed v8.0.8 engine is missing: $INSTALLED_ENGINE"

  echo "Restoring existing v8.1.5 bridge LaunchAgent..."
  /bin/launchctl bootstrap "gui/$UID_NUM" "$BRIDGE_PLIST"
  /bin/launchctl kickstart -k "gui/$UID_NUM/$LABEL"
  /bin/sleep 2
  /bin/launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1 || fail "Existing bridge LaunchAgent did not load."
}

rollback_on_error() {
  trap - ERR
  set +e

  echo
  echo "v8.1.6 installation did not complete. Restoring the prior running bridge state..."

  if [[ "$MOTION_AGENT_LOADED" -eq 1 ]]; then
    /bin/launchctl bootout "gui/$UID_NUM" "$MOTION_PLIST" >/dev/null 2>&1 || true
  fi

  ensure_bridge_loaded >/dev/null 2>&1 || true
  cleanup_tmp

  echo "Rollback attempt finished. The v8.0.8 engine and v8.1.5 bridge component were not replaced."
}

trap rollback_on_error ERR

if /usr/bin/pgrep -x Traktor >/dev/null 2>&1; then
  fail "Traktor is running. Close Traktor before installing v8.1.6."
fi

[[ -d "$REPO/.git" ]] || fail "Expected qualified repository not found: $REPO"
[[ -f "$SOURCE" ]] || fail "Missing v8.0.8 source: $SOURCE"
[[ -x "$BUILD_SCRIPT" || -f "$BUILD_SCRIPT" ]] || fail "Missing v8.0.8 build script: $BUILD_SCRIPT"
[[ -f "$MOTION_SOURCE" ]] || fail "Missing v8.1.6 Reduce Motion source: $MOTION_SOURCE"
[[ -f "$BRIDGE_PLIST" ]] || fail "Existing v8.1.5 bridge LaunchAgent plist is missing: $BRIDGE_PLIST"
[[ -x "$BRIDGE_SUPERVISOR" ]] || fail "Existing v8.1.5 bridge supervisor is missing: $BRIDGE_SUPERVISOR"
[[ -x "$INSTALLED_ENGINE" ]] || fail "Installed v8.0.8 engine is missing: $INSTALLED_ENGINE"

SOURCE_SHA="$(/usr/bin/shasum -a 256 "$SOURCE" | /usr/bin/awk '{print $1}')"
[[ "$SOURCE_SHA" == "$EXPECTED_SOURCE_SHA" ]] || fail "v8.0.8 source checksum mismatch."

/bin/mkdir -p "$APP_DIR" "$LOG_DIR" "$PLIST_DIR"

# Build the unchanged qualified engine before touching the running candidate/service.
echo "Building and validating unchanged engine v$ENGINE_VERSION..."
/bin/bash "$BUILD_SCRIPT"
[[ -x "$BUILT_ENGINE" ]] || fail "v8.0.8 build output is missing."
BUILT_ENGINE_SHA="$(/usr/bin/shasum -a 256 "$BUILT_ENGINE" | /usr/bin/awk '{print $1}')"
[[ "$BUILT_ENGINE_SHA" == "$EXPECTED_ENGINE_SHA" ]] || fail "v8.0.8 binary checksum mismatch on the qualified Mac."

# Compile to the final production path before the permission test. Full Disk
# Access is granted to this exact executable path, not to the installer shell.
echo "Compiling v8.1.6 Reduce Motion helper..."
/usr/bin/clang -fobjc-arc \
  -framework Foundation \
  -framework AppKit \
  -framework CoreFoundation \
  "$MOTION_SOURCE" \
  -o "$MOTION_HELPER"
/bin/chmod 755 "$MOTION_HELPER"

# This rewrites the current state to itself, so it proves protected preference
# access without visibly toggling Reduce Motion.
echo "Checking Full Disk Access for the production Reduce Motion helper..."
set +e
"$MOTION_HELPER" --permission-test
FDA_STATUS=$?
set -e

if [[ "$FDA_STATUS" -ne 0 ]]; then
  echo
  echo "FULL DISK ACCESS REQUIRED ONCE"
  echo
  echo "Add this exact executable in System Settings -> Privacy & Security -> Full Disk Access:"
  echo "$MOTION_HELPER"
  echo
  echo "Turn it ON, then run this same installer again."
  echo "No running candidate or installed bridge service was stopped."
  /usr/bin/open -R "$MOTION_HELPER" >/dev/null 2>&1 || true
  /usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" >/dev/null 2>&1 || true
  trap - ERR
  cleanup_tmp
  exit 2
fi

echo "Full Disk Access check PASSED."

TMP_DIR="$(/usr/bin/mktemp -d)"
MOTION_PLIST_TMP="$TMP_DIR/$MOTION_LABEL.plist"

/bin/cat > "$MOTION_PLIST_TMP" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$MOTION_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$MOTION_HELPER</string>
    <string>--guard</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>5</integer>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/reduce_motion_guard_v8_1_6_launchd.out</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/reduce_motion_guard_v8_1_6_launchd.err</string>
</dict>
</plist>
EOF_PLIST

/usr/bin/plutil -lint "$MOTION_PLIST_TMP"

if ! /bin/launchctl print "system/$SPOTLIGHT_LABEL" >/dev/null 2>&1; then
  fail "The qualified v8.1.5 Spotlight guard is not loaded. Restore v8.1.5 before installing v8.1.6."
fi
[[ -x "$ROOT_SPOTLIGHT_GUARD" ]] || fail "The installed v8.1.5 Spotlight guard executable is missing."
[[ -f "$ROOT_SPOTLIGHT_PLIST" ]] || fail "The installed v8.1.5 Spotlight LaunchDaemon plist is missing."

# Candidate v5 is the accepted test runtime. Stop it cleanly only after every
# production prerequisite above has passed. Its motion helper restores the
# pre-Traktor state on TERM.
stop_test_candidates

# Candidate testing booted out v8.1.5 without replacing its files. Put that
# already-qualified bridge component back under launchd supervision.
ensure_bridge_loaded

# Replace only the v8.1.6 motion LaunchAgent. The engine, bridge supervisor and
# Spotlight guard remain the already-qualified components.
/bin/launchctl bootout "gui/$UID_NUM" "$MOTION_PLIST" >/dev/null 2>&1 || true
/bin/cp "$MOTION_PLIST_TMP" "$MOTION_PLIST"
/bin/chmod 644 "$MOTION_PLIST"
/bin/launchctl bootstrap "gui/$UID_NUM" "$MOTION_PLIST"
MOTION_AGENT_LOADED=1
/bin/launchctl kickstart -k "gui/$UID_NUM/$MOTION_LABEL"
/bin/sleep 2
/bin/launchctl print "gui/$UID_NUM/$MOTION_LABEL" >/dev/null 2>&1 || fail "v8.1.6 Reduce Motion LaunchAgent did not load."

printf '%s\n' "$PACKAGE_VERSION" > "$PACKAGE_MARKER"
/bin/chmod 644 "$PACKAGE_MARKER"

SUCCESS=1
trap - ERR
cleanup_tmp

echo
echo "INSTALLATION PASSED"
echo "Service/package: v$PACKAGE_VERSION"
echo "Engine: v$ENGINE_VERSION (unchanged)"
echo "Bridge supervisor component: v$BRIDGE_COMPONENT_VERSION (unchanged)"
echo "Spotlight guard: $SPOTLIGHT_LABEL (v8.1.5 component, unchanged)"
echo "Reduce Motion guard: $MOTION_LABEL (v8.1.6)"
echo "Effective Reduce Motion now: $(motion_state)"
echo
echo "No Dock/Finder restart is used by the Reduce Motion guard."
