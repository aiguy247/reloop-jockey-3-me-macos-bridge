#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]
DIST = ROOT / "dist"
SOURCE_ROOT = ROOT / "release/v8.1.7"
NAME = "Reloop_Bridge_v8_1_7_CANDIDATE7"
ZIP = DIST / "Reloop_Jockey_3_ME_Bridge_v8_1_7.zip"
SHA = DIST / "Reloop_Jockey_3_ME_Bridge_v8_1_7.zip.sha256"
EXPECTED = "8ebc35f548ec231c64214f68a7e481d5885d093e1b10ce2cfbfde6a0b48a801d"
FIXED_TIME = (2026, 10, 23, 18, 15, 0)

FILES = [
    "CODE_REVIEW.md",
    "PACKAGE_MANIFEST.json",
    "README_FIRST.md",
    "SHA256SUMS.txt",
    "install.sh",
    "rollback_automation_only.sh",
    "source/ReloopDJWatchGuard.m",
    "source/ReloopSpotlightEventGuard.m",
    "source/reloop_bridge_service_v8_1_5.sh",
    "status.sh",
]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def add_file(zf: zipfile.ZipFile, rel: str) -> None:
    src = SOURCE_ROOT / rel
    if not src.is_file():
        raise SystemExit(f"Missing qualified Candidate 7 input: {src}")

    info = zipfile.ZipInfo(f"{NAME}/{rel}")
    info.date_time = FIXED_TIME
    info.external_attr = ((0o755 if rel.endswith(".sh") else 0o644) & 0xFFFF) << 16
    zf.writestr(
        info,
        src.read_bytes(),
        compress_type=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    )


def main() -> None:
    DIST.mkdir(parents=True, exist_ok=True)
    if ZIP.exists():
        ZIP.unlink()

    with zipfile.ZipFile(
        ZIP, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as zf:
        for rel in sorted(FILES):
            add_file(zf, rel)

    digest = sha256(ZIP)
    if digest != EXPECTED:
        raise SystemExit(
            "Reconstructed Candidate 7 ZIP differs from physically-qualified artifact: "
            f"expected {EXPECTED}, got {digest}"
        )

    SHA.write_text(f"{digest}  {ZIP.name}\n", encoding="utf-8")
    print(ZIP)
    print(SHA)
    print(digest)


if __name__ == "__main__":
    main()
