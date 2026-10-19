#!/bin/bash
set -u
set -o pipefail

LEGACY_LABEL="com.guy.reloopbridge"
UID_NUM="$(/usr/bin/id -u)"
LEGACY_PLIST="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
LEGACY_WAS_LOADED=0
RESTORED=0

restore_legacy() {
  if [[ "$RESTORED" -eq 1 ]]; then
    return 0
  fi
  RESTORED=1

  if [[ "$LEGACY_WAS_LOADED" -eq 1 ]]; then
    echo
    echo "Restoring qualified v8.1.3 service..."
    if [[ ! -f "$LEGACY_PLIST" ]]; then
      echo "ERROR: Cannot restore qualified service; plist is missing: $LEGACY_PLIST"
      return 1
    fi
    /bin/launchctl bootstrap "gui/$UID_NUM" "$LEGACY_PLIST" >/dev/null 2>&1 || true
    /bin/launchctl kickstart -k "gui/$UID_NUM/$LEGACY_LABEL" >/dev/null 2>&1 || true
    if /bin/launchctl print "gui/$UID_NUM/$LEGACY_LABEL" >/dev/null 2>&1; then
      echo "Qualified v8.1.3 service restored."
    else
      echo "WARNING: Automatic restore did not leave the qualified service loaded."
      echo "Run tools/phase4/restore_qualified_v8_1_3.sh from this repository."
      return 1
    fi
  fi
}

main() {
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
  BUILD_SCRIPT="$SCRIPT_DIR/build_diagnostic_v8_0_6.sh"
  SNAPSHOT_SCRIPT="$SCRIPT_DIR/capture_usb_environment.sh"
  ENGINE="$REPO_DIR/build/reloop_bridge_engine_v8_0_6_phase4_diagnostics"

  /bin/bash "$BUILD_SCRIPT" || return 1
  /bin/bash "$SNAPSHOT_SCRIPT" "foreground-v8.0.6-pretest" || return 1

  if /bin/launchctl print "gui/$UID_NUM/$LEGACY_LABEL" >/dev/null 2>&1; then
    LEGACY_WAS_LOADED=1
    if [[ ! -f "$LEGACY_PLIST" ]]; then
      echo "ERROR: Qualified service is loaded but its plist is missing. Nothing changed."
      return 1
    fi
    echo
    echo "Stopping qualified v8.1.3 service for the foreground candidate test..."
    /bin/launchctl bootout "gui/$UID_NUM" "$LEGACY_PLIST" || return 1
    /bin/sleep 1
    if /bin/launchctl print "gui/$UID_NUL/$LEGACY_LABEL" >/dev/null 2>&1; then
      echo "ERROR: Qualified service is still loaded. Candidate was not started."
      return 1
    fi
  fi

  trap restore_legacy EXIT

  echo
  echo "STARTING FOREGROUND PHASE 4 CANDIDATE v8.0.6"
  echo "Control-C stops the candidate. The qualified v8.1.3 service will then be restored if it was loaded before this test."
  echo
  "$ENGINE"
  CANDIDATE_STATUS=$?

  restore_legacy
  trap - EXIT

  echo
  echo "Foreground candidate finished with status $CANDIDATE_STATUS."
  return "$CANDIDATE_STATUS"
}

main "$@"
