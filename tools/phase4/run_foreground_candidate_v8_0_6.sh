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

  RUN_LABEL="${1:-hama-smoke}"
  SAFE_LABEL="$(printf '%s' "$RUN_LABEL" | /usr/bin/tr -cs '[:alnum:]_.-' '_' | /usr/bin/sed 's/^_*//;s/_*$//')"
  [[ -n "$SAFE_LABEL" ]] || SAFE_LABEL="unlabeled"
  STAMP="$(/bin/date '+%Y%m%d-%H%M%S')"
  RUN_ROOT="$HOME/Library/Logs/ReloopBridge/Phase4Runs"
  RUN_LOG="$RUN_ROOT/${STAMP}-${SAFE_LABEL}-v8.0.6-console.log"
  /bin/mkdir -p "$RUN_ROOT" || return 1

  PCM_ROOT="$HOME/Library/Logs/ReloopBridge/Phase4PCM"
  if /usr/bin/find "$PCM_ROOT" -maxdepth 1 -type f \( -name 'usb_stall_*.wav' -o -name 'usb_stall_*.json' \) -print -quit 2>/dev/null | /usr/bin/grep -q .; then
    PCM_ARCHIVE="$PCM_ROOT/archive/${STAMP}-before-${SAFE_LABEL}"
    /bin/mkdir -p "$PCM_ARCHIVE" || return 1
    /usr/bin/find "$PCM_ROOT" -maxdepth 1 -type f \( -name 'usb_stall_*.wav' -o -name 'usb_stall_*.json' \) -exec /bin/mv {} "$PCM_ARCHIVE/" \; || return 1
    echo "Archived previous Phase 4 PCM captures: $PCM_ARCHIVE"
  fi

  /bin/bash "$BUILD_SCRIPT" || return 1
  /bin/bash "$SNAPSHOT_SCRIPT" "${SAFE_LABEL}-v8.0.6-pretest" || return 1

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
    if /bin/launchctl print "gui/$UID_NUM/$LEGACY_LABEL" >/dev/null 2>&1; then
      echo "ERROR: Qualified service is still loaded. Candidate was not started."
      return 1
    fi
  fi

  trap restore_legacy EXIT

  echo
  echo "STARTING FOREGROUND PHASE 4 CANDIDATE v8.0.6"
  echo "Run label: $RUN_LABEL"
  echo "Console log: $RUN_LOG"
  echo "Control-C stops the candidate. The qualified v8.1.3 service will then be restored if it was loaded before this test."
  echo

  "$ENGINE" 2>&1 | (
    trap '' INT
    /usr/bin/tee "$RUN_LOG"
  )
  CANDIDATE_STATUS="${PIPESTATUS[0]}"

  restore_legacy
  trap - EXIT

  echo
  echo "Foreground candidate finished with status $CANDIDATE_STATUS."
  echo "Console log saved: $RUN_LOG"
  return "$CANDIDATE_STATUS"
}

main "$@"
