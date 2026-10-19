#!/bin/bash
set -u
set -o pipefail

main() {
  LABEL="com.guy.reloopbridge"
  UID_NUM="$(/usr/bin/id -u)"
  PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

  if /bin/launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
    echo "Qualified v8.1.3 service is already loaded."
    return 0
  fi

  if [[ ! -f "$PLIST" ]]; then
    echo "ERROR: Qualified v8.1.3 LaunchAgent plist is missing: $PLIST"
    return 1
  fi

  /bin/launchctl bootstrap "gui/$UID_NUM" "$PLIST" || return 1
  /bin/launchctl kickstart -k "gui/$UID_NUM/$LABEL" || return 1

  if /bin/launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
    echo "Qualified v8.1.3 service restored."
    return 0
  fi

  echo "ERROR: Restore command ran but the qualified service is not loaded."
  return 1
}

main "$@"
