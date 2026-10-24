#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
DIST = ROOT / "dist"
SOURCE = ROOT / "release/v8.1.7/Reloop_Bridge_v8_1_7_CANDIDATE7.zip"
ZIP = DIST / "Reloop_Jockey_3_ME_Bridge_v8_1_7.zip"
SHA = DIST / "Reloop_Jockey_3_ME_Bridge_v8_1_7.zip.sha256"
EXPECTED = "8ebc35f548ec231c64214f68a7e481d5885d093e1b10ce2cfbfde6a0b48a801d"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"Missing physically-qualified artifact: {SOURCE}")

    source_sha = sha256(SOURCE)
    if source_sha != EXPECTED:
        raise SystemExit(
            f"Qualified Candidate 7 SHA mismatch: expected {EXPECTED}, got {source_sha}"
        )

    DIST.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SOURCE, ZIP)

    release_sha = sha256(ZIP)
    if release_sha != EXPECTED:
        raise SystemExit("Release copy differs from qualified Candidate 7 bytes")

    SHA.write_text(f"{release_sha}  {ZIP.name}\n", encoding="utf-8")
    print(ZIP)
    print(SHA)
    print(release_sha)


if __name__ == "__main__":
    main()
