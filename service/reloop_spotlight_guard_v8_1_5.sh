#!/bin/bash
set -u

VERSION="8.1.5"
TRAKTOR_PROCESS="Traktor"
ROOT_VOLUME="/"
STATE_DIR="/var/db/com.guy.reloopbridge"
STATE_FILE="$STATE_DIR/spotlight-indexing-before-traktor"
LOG_DIR="/Library/Logs/ReloopBridge"
LOG_FILE="$LOG_DIR/spotlight_guard_v8_1_5.log"
POLL_SECONDS=2

stop_requested=0
last_traktor_state="unknown"

/bin/mkdir -p "$STATE_DIR" "$LOG_DIR"
/bin/chmod 755 "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true
/bin/chmod 644 "$LOG_FILE" 2>/dev/null || true

stamp() { /bin/date "+%Y-%m-%d %H:%M:%S"; }

log_msg() {
  echo "$(stamp) | $*" >> "$LOG_FILE"
}

spotlight_status_text() {
  /usr/bin/mdutil -s "$ROOT_VOLUME" 2>&1
}

spotlight_state() {
  local status
  status="$(spotlight_status_text)"
  if echo "$status" | /usr/bin/grep -Fq "Indexing enabled"; then
    echo "enabled"
  elif echo "$status" | /usr/bin/grep -Fq "Indexing disabled"; then
    echo "disabled"
  else
    echo "unknown"
  fi
}

traktor_running() {
  /usr/bin/pgrep -x "$TRAKTOR_PROCESS" >/dev/null 2>&1
}

remember_pre_traktor_state() {
  [[ -f "$STATE_FILE" ]] && return 0

  local state
  state="$(spotlight_state)"
  case "$state" in
    enabled|disabled)
      echo "$state" > "$STATE_FILE"
      ;;
    *)
      echo "unknown" > "$STATE_FILE"
      ;;
  esac
  /bin/chmod 600 "$STATE_FILE" 2>/dev/null || true
  log_msg "Saved pre-Traktor Spotlight indexing state: $state."
}

disable_indexing_for_traktor() {
  local state
  state="$(spotlight_state)"

  if [[ "$state" == "disabled" ]]; then
    return 0
  fi

  log_msg "Traktor is running; disabling Spotlight indexing for $ROOT_VOLUME."
  if /usr/bin/mdutil -i off "$ROOT_VOLUME" >> "$LOG_FILE" 2>&1; then
    state="$(spotlight_state)"
    log_msg "Spotlight indexing state after disable request: $state."
  else
    log_msg "ERROR: mdutil failed while disabling Spotlight indexing."
    return 1
  fi
}

restore_indexing_if_needed() {
  [[ -f "$STATE_FILE" ]] || return 0

  local saved
  saved="$(/bin/cat "$STATE_FILE" 2>/dev/null || echo unknown)"

  case "$saved" in
    enabled)
      log_msg "Traktor is not running; restoring Spotlight indexing to enabled."
      if /usr/bin/mdutil -i on "$ROOT_VOLUME" >> "$LOG_FILE" 2>&1; then
        log_msg "Spotlight indexing state after restore: $(spotlight_state)."
        /bin/rm -f "$STATE_FILE"
      else
        log_msg "ERROR: mdutil failed while restoring Spotlight indexing. State file retained."
        return 1
      fi
      ;;
    disabled)
      log_msg "Traktor is not running; Spotlight was already disabled before Traktor. Leaving it disabled."
      /bin/rm -f "$STATE_FILE"
      ;;
    *)
      log_msg "WARNING: Previous Spotlight state is unknown. Leaving indexing unchanged."
      /bin/rm -f "$STATE_FILE"
      ;;
  esac
}

handle_signal() {
  stop_requested=1
}

trap handle_signal INT TERM HUP

log_msg "Spotlight guard v$VERSION started."

# Recover cleanly after a daemon crash/reboot. If a prior run left a state file
# and Traktor is no longer running, restore the saved state before monitoring.
if ! traktor_running; then
  restore_indexing_if_needed || true
fi

while [[ "$stop_requested" -eq 0 ]]; do
  if traktor_running; then
    if [[ "$last_traktor_state" != "running" ]]; then
      log_msg "Traktor detected."
      remember_pre_traktor_state
    fi
    disable_indexing_for_traktor || true
    last_traktor_state="running"
  else
    if [[ "$last_traktor_state" == "running" ]]; then
      log_msg "Traktor no longer detected."
    fi
    restore_indexing_if_needed || true
    last_traktor_state="stopped"
  fi

  /bin/sleep "$POLL_SECONDS" &
  wait $! 2>/dev/null || true
done

log_msg "Spotlight guard stopping."
restore_indexing_if_needed || true
log_msg "Spotlight guard stopped."
