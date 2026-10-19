#!/bin/bash
set -u
set -o pipefail

main() {
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
  BASE_SOURCE="$REPO_DIR/src/reloop_jockey3_bridge_v8_0_4_master_play_flash_48k.m"
  PATCH_FILE="$REPO_DIR/patches/phase4/ENGINE_DIFF_v8_0_4_to_v8_0_6.patch"
  BUILD_DIR="$REPO_DIR/build"
  GENERATED_DIR="$BUILD_DIR/phase4-generated"
  GENERATED_SOURCE="$GENERATED_DIR/reloop_jockey3_bridge_v8_0_6_phase4_diagnostics_48k.m"
  ENGINE="$BUILD_DIR/reloop_bridge_engine_v8_0_6_phase4_diagnostics"

  EXPECTED_BASE_SHA="344a9572c2ada2b3c4e2839f2a91a8416eddb5236eb06963e1b6c0d1b54b3398"
  EXPECTED_PATCH_SHA="de98acbd48f939aa199569027861720a5cc4bb80b4592ca1d891bb9c8722209f"
  EXPECTED_GENERATED_SHA="25894116213bce18c46a476f9c1607a76032ca27c3a73d03cd2ee25245005c04"

  if [[ ! -f "$BASE_SOURCE" ]]; then
    echo "ERROR: Qualified v8.0.4 source is missing: $BASE_SOURCE"
    return 1
  fi

  if [[ ! -f "$PATCH_FILE" ]]; then
    echo "ERROR: Phase 4 patch is missing: $PATCH_FILE"
    return 1
  fi

  ACTUAL_BASE_SHA="$(/usr/bin/shasum -a 256 "$BASE_SOURCE" | /usr/bin/awk '{print $1}')"
  if [[ "$ACTUAL_BASE_SHA" != "$EXPECTED_BASE_SHA" ]]; then
    echo "ERROR: Qualified v8.0.4 source checksum mismatch. Nothing built."
    echo "Expected: $EXPECTED_BASE_SHA"
    echo "Actual:   $ACTUAL_BASE_SHA"
    return 1
  fi

  ACTUAL_PATCH_SHA="$(/usr/bin/shasum -a 256 "$PATCH_FILE" | /usr/bin/awk '{print $1}')"
  if [[ "$ACTUAL_PATCH_SHA" != "$EXPECTED_PATCH_SHA" ]]; then
    echo "ERROR: Phase 4 patch checksum mismatch. Nothing built."
    echo "Expected: $EXPECTED_PATCH_SHA"
    echo "Actual:   $ACTUAL_PATCH_SHA"
    return 1
  fi

  /bin/mkdir -p "$BUILD_DIR" "$GENERATED_DIR" || return 1
  /bin/rm -f "$GENERATED_SOURCE" "$ENGINE"
  /bin/cp "$BASE_SOURCE" "$GENERATED_SOURCE" || return 1

  echo "Generating Phase 4 v8.0.6 source from the exact qualified v8.0.4 source..."
  /usr/bin/patch "$GENERATED_SOURCE" "$PATCH_FILE" || return 1

  ACTUAL_GENERATED_SHA="$(/usr/bin/shasum -a 256 "$GENERATED_SOURCE" | /usr/bin/awk '{print $1}')"
  if [[ "$ACTUAL_GENERATED_SHA" != "$EXPECTED_GENERATED_SHA" ]]; then
    echo "ERROR: Generated Phase 4 source checksum mismatch. Nothing compiled."
    echo "Expected: $EXPECTED_GENERATED_SHA"
    echo "Actual:   $ACTUAL_GENERATED_SHA"
    return 1
  fi

  echo "Building Phase 4 diagnostic engine v8.0.6..."
  /usr/bin/clang -fobjc-arc \
    -framework Foundation \
    -framework CoreAudio \
    -framework CoreMIDI \
    -framework IOKit \
    -framework IOUSBHost \
    "$GENERATED_SOURCE" \
    -o "$ENGINE" || return 1

  /bin/chmod 755 "$ENGINE" || return 1

  echo
  echo "BUILD PASSED"
  echo "Qualified base SHA-256: $ACTUAL_BASE_SHA"
  echo "Phase 4 patch SHA-256:  $ACTUAL_PATCH_SHA"
  echo "Generated source SHA-256: $ACTUAL_GENERATED_SHA"
  echo "Generated source: $GENERATED_SOURCE"
  echo "Engine: $ENGINE"
  /usr/bin/file "$ENGINE"
  /usr/bin/shasum -a 256 "$ENGINE"
}

main "$@"
