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
