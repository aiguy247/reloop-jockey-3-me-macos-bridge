#!/bin/bash
set -u
set -o pipefail

main() {
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
  BASE_SOURCE="$REPO_DIR/src/reloop_jockey3_bridge_v8_0_4_master_play_flash_48k.m"
  V806_PATCH="$REPO_DIR/patches/phase4/ENGINE_DIFF_v8_0_4_to_v8_0_6.patch"
  V807_SOURCE="$REPO_DIR/src/phase4/reloop_jockey3_bridge_v8_0_7_phase4_diagnostics_48k.m"
  BUILD_DIR="$REPO_DIR/build"
  GENERATED_DIR="$BUILD_DIR/phase4-generated"
  V806_GENERATED="$GENERATED_DIR/reloop_jockey3_bridge_v8_0_6_phase4_diagnostics_48k.m"
  ENGINE="$BUILD_DIR/reloop_bridge_engine_v8_0_7_phase4_diagnostics"

  EXPECTED_BASE_SHA="344a9572c2ada2b3c4e2839f2a91a8416eddb5236eb06963e1b6c0d1b54b3398"
  EXPECTED_V806_PATCH_SHA="de98acbd48f939aa199569027861720a5cc4bb80b4592ca1d891bb9c8722209f"
  EXPECTED_V806_GENERATED_SHA="25894116213bce18c46a476f9c1607a76032ca27c3a73d03cd2ee25245005c04"
  EXPECTED_V807_SOURCE_SHA="d3bb264fc994648f448a4ec77839b530cacadae34ff4f898588cf8c66730a2e8"

  for REQUIRED in "$BASE_SOURCE" "$V806_PATCH" "$V807_SOURCE"; do
    if [[ ! -f "$REQUIRED" ]]; then
      echo "ERROR: Required Phase 4 input is missing: $REQUIRED"
      return 1
    fi
  done

  ACTUAL_BASE_SHA="$(/usr/bin/shasum -a 256 "$BASE_SOURCE" | /usr/bin/awk '{print $1}')"
  ACTUAL_V806_PATCH_SHA="$(/usr/bin/shasum -a 256 "$V806_PATCH" | /usr/bin/awk '{print $1}')"
  ACTUAL_V807_SOURCE_SHA="$(/usr/bin/shasum -a 256 "$V807_SOURCE" | /usr/bin/awk '{print $1}')"

  if [[ "$ACTUAL_BASE_SHA" != "$EXPECTED_BASE_SHA" ]]; then
    echo "ERROR: Qualified v8.0.4 source checksum mismatch. Nothing built."
    return 1
  fi
  if [[ "$ACTUAL_V806_PATCH_SHA" != "$EXPECTED_V806_PATCH_SHA" ]]; then
    echo "ERROR: v8.0.6 diagnostic patch checksum mismatch. Nothing built."
    return 1
  fi
  if [[ "$ACTUAL_V807_SOURCE_SHA" != "$EXPECTED_V807_SOURCE_SHA" ]]; then
    echo "ERROR: v8.0.7 diagnostic source checksum mismatch. Nothing built."
    echo "Expected: $EXPECTED_V807_SOURCE_SHA"
    echo "Actual:   $ACTUAL_V807_SOURCE_SHA"
    return 1
  fi

  /bin/mkdir -p "$BUILD_DIR" "$GENERATED_DIR" || return 1
  /bin/rm -f "$V806_GENERATED" "$ENGINE"
  /bin/cp "$BASE_SOURCE" "$V806_GENERATED" || return 1
  /usr/bin/patch "$V806_GENERATED" "$V806_PATCH" >/dev/null || return 1

  ACTUAL_V806_GENERATED_SHA="$(/usr/bin/shasum -a 256 "$V806_GENERATED" | /usr/bin/awk '{print $1}')"
  if [[ "$ACTUAL_V806_GENERATED_SHA" != "$EXPECTED_V806_GENERATED_SHA" ]]; then
    echo "ERROR: Reconstructed v8.0.6 parent checksum mismatch. Nothing compiled."
    echo "Expected: $EXPECTED_V806_GENERATED_SHA"
    echo "Actual:   $ACTUAL_V806_GENERATED_SHA"
    return 1
  fi

  echo "Building Phase 4 diagnostic engine v8.0.7..."
  /usr/bin/clang -fobjc-arc     -framework Foundation     -framework CoreAudio     -framework CoreMIDI     -framework IOKit     -framework IOUSBHost     "$V807_SOURCE"     -o "$ENGINE" || return 1

  /bin/chmod 755 "$ENGINE" || return 1

  echo
  echo "BUILD PASSED"
  echo "Qualified base SHA-256:       $ACTUAL_BASE_SHA"
  echo "v8.0.6 patch SHA-256:         $ACTUAL_V806_PATCH_SHA"
  echo "v8.0.6 parent source SHA-256: $ACTUAL_V806_GENERATED_SHA"
  echo "v8.0.7 source SHA-256:        $ACTUAL_V807_SOURCE_SHA"
  echo "Engine: $ENGINE"
  /usr/bin/file "$ENGINE"
  /usr/bin/shasum -a 256 "$ENGINE"
}

main "$@"
