#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_ZIP="$SCRIPT_DIR/Reloop_Controller_Bridge_v8_1_3.zip"
EXPECTED_ZIP_SHA="5255a15b3f9062b6df068daa0f118079306e8e6a5e3ac6e408612bac074aa908"

if [[ ! -f "$PACKAGE_ZIP" ]]; then
  echo "ERROR: Package ZIP not found:"
  echo "  $PACKAGE_ZIP"
  echo
  echo "Put Reloop_Controller_Bridge_v8_1_3.zip in the same folder as this script."
  exit 1
fi

ACTUAL_ZIP_SHA="$(/usr/bin/shasum -a 256 "$PACKAGE_ZIP" | /usr/bin/awk '{print $1}')"
if [[ "$ACTUAL_ZIP_SHA" != "$EXPECTED_ZIP_SHA" ]]; then
  echo "ERROR: Package ZIP SHA-256 mismatch."
  echo "Expected: $EXPECTED_ZIP_SHA"
  echo "Actual:   $ACTUAL_ZIP_SHA"
  exit 1
fi

TMP="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$TMP"' EXIT

/usr/bin/unzip -q "$PACKAGE_ZIP" -d "$TMP"

INSTALLER="$TMP/Reloop_Controller_Bridge_v8_1_3/service/install_or_upgrade_reloop_bridge_service_v8_1_3.sh"
if [[ ! -f "$INSTALLER" ]]; then
  echo "ERROR: Installer missing from package."
  exit 1
fi

/bin/bash "$INSTALLER"
