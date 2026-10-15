# Qualified Traktor mapping

Authoritative mapping:

`Reloop_CURRENT_QUALIFIED_BASELINE_AB-playpause-flash_2026-10-09.tsi`

SHA-256 of the uncompressed original:

`4d0dc9f346507f86a6b084560638b8c5b5fa71b4a2c1af702d6961552046840e`

The repository stores it as an `.xz` file to keep the Git object small while preserving the exact original bytes.

Restore it on macOS:

```bash
xz -dk Reloop_CURRENT_QUALIFIED_BASELINE_AB-playpause-flash_2026-10-09.tsi.xz
shasum -a 256 Reloop_CURRENT_QUALIFIED_BASELINE_AB-playpause-flash_2026-10-09.tsi
```

The checksum must match exactly before treating the file as the qualified baseline.
