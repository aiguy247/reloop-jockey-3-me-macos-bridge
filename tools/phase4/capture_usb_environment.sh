#!/bin/bash
set -u
set -o pipefail

main() {
  LABEL="${1:-unlabeled}"
  SAFE_LABEL="$(printf '%s' "$LABEL" | /usr/bin/tr -cs '[:alnum:]_.-' '_' | /usr/bin/sed 's/^_*//;s/_*$//')"
  [[ -n "$SAFE_LABEL" ]] || SAFE_LABEL="unlabeled"

  STAMP="$(/bin/date '+%Y%m%d-%H%M%S')"
  ROOT="$HOME/Library/Logs/ReloopBridge/Phase4Runs"
  OUT="$ROOT/${STAMP}-${SAFE_LABEL}"
  /bin/mkdir -p "$OUT" || return 1

  {
    echo "Phase 4 USB environment snapshot"
    echo "Label: $LABEL"
    echo "Captured: $(/bin/date '+%Y-%m-%d %H:%M:%S %z')"
    echo
    echo "== macOS =="
    /usr/bin/sw_vers 2>&1 || true
    echo
    echo "== kernel =="
    /usr/bin/uname -a 2>&1 || true
    echo
    echo "== power source =="
    /usr/bin/pmset -g batt 2>&1 || true
    echo
    echo "== thermal state =="
    /usr/bin/pmset -g therm 2>&1 || true
    echo
    echo "== memory pressure =="
    /usr/bin/memory_pressure 2>&1 || true
    echo
    echo "== root filesystem free space =="
    /bin/df -h / 2>&1 || true
    echo
    echo "== qualified service state =="
    /bin/launchctl print "gui/$(/usr/bin/id -u)/com.guy.reloopbridge" 2>&1 | \
      /usr/bin/grep -E 'state =|pid =|last exit code' || true
    echo
    echo "== Traktor process =="
    /usr/bin/pgrep -fl 'Traktor' 2>&1 || true
    echo
    echo "== Audio System Trace tooling =="
    if /usr/bin/xcrun --find xctrace >/dev/null 2>&1; then
      /usr/bin/xcrun xctrace version 2>&1 || true
    else
      echo "xctrace not available through the active developer tools."
    fi
  } > "$OUT/environment.txt"

  /usr/sbin/system_profiler SPHardwareDataType SPPowerDataType SPUSBDataType SPThunderboltDataType SPAudioDataType \
    > "$OUT/system_profiler.txt" 2>&1 || true
  /usr/sbin/ioreg -p IOUSB -l -w 0 > "$OUT/ioreg_usb.txt" 2>&1 || true
  /usr/sbin/ioreg -p IOService -n 'Reloop Jockey 3 ME' -r -l \
    > "$OUT/ioreg_reloop.txt" 2>&1 || true
  /usr/bin/pmset -g custom > "$OUT/power_settings.txt" 2>&1 || true

  echo "PHASE 4 ENVIRONMENT SNAPSHOT SAVED"
  echo "$OUT"
}

main "$@"
