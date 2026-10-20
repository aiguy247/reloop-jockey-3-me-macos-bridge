#!/bin/bash
set -u

main() {
  PATTERN="reloop_bridge_engine_v8_0_8_phase4_recovery_diagnostics"
  PIDS="$(/usr/bin/pgrep -f "$PATTERN" 2>/dev/null || true)"
  COUNT="$(printf '%s\n' "$PIDS" | /usr/bin/awk 'NF {count++} END {print count+0}')"

  if [[ "$COUNT" -eq 0 ]]; then
    echo "ERROR: Phase 4 v8.0.8 candidate is not running."
    return 1
  fi
  if [[ "$COUNT" -ne 1 ]]; then
    echo "ERROR: Expected one v8.0.8 candidate process; found $COUNT. Nothing signaled."
    printf '%s\n' "$PIDS"
    return 1
  fi

  PID="$(printf '%s\n' "$PIDS" | /usr/bin/awk 'NF {print; stop=1} stop {next}')"
  /bin/kill -USR1 "$PID" || return 1
  echo "Manual pre-USB PCM snapshot requested from v8.0.8 (PID $PID)."
}

main "$@"
