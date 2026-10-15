# Security and privacy notes

## Privilege model

The qualified bridge/service setup runs in the user's macOS session. Compilation and the qualified installation flow do not require `sudo`.

## Network behavior

The qualified v8.0.4 bridge source contains no HTTP client, socket connection, shell-command execution or credential handling path identified in the public-readiness audit.

Its external interfaces are local macOS/USB/audio/MIDI facilities, primarily:

- IOUSBHost;
- CoreAudio;
- CoreMIDI;
- BlackHole audio device.

## Firmware

This repository does not distribute a controller firmware image. The qualified bridge does not perform a firmware-update workflow.

## Files written by the qualified service wrapper

The preserved v8.1.3 service wrapper uses locations under the current user's home directory, including:

- `~/Library/Application Support/ReloopBridge`;
- `~/Library/Logs/ReloopBridge`;
- `~/Library/LaunchAgents`;
- a historical project working directory documented in `service/README.md`.

A future portable installer should remove the historical project-directory assumption.

## Logs

Runtime logs and audio captures are intentionally excluded by `.gitignore`.

Logs can contain timestamps, process/session state and diagnostic measurements. Review them before posting publicly.

## Credentials

The project does not require GitHub credentials, API keys or application secrets at runtime.

If credentials or personal data are ever committed accidentally, stop publication and rewrite/purge history before making the repository public.
