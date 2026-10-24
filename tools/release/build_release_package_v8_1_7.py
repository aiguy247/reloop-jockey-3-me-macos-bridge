#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]
DIST = ROOT / "dist"
ARTIFACT_DIR = ROOT / "release/v8.1.7/artifact"
ZIP = DIST / "Reloop_Jockey_3_ME_Bridge_v8_1_7.zip"
SHA = DIST / "Reloop_Jockey_3_ME_Bridge_v8_1_7.zip.sha256"
EXPECTED = "8ebc35f548ec231c64214f68a7e481d5885d093e1b10ce2cfbfde6a0b48a801d"
EXPECTED_SIZE = 26530


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    parts = sorted(
        ARTIFACT_DIR.glob("Reloop_Bridge_v8_1_7_CANDIDATE7.zip.b64.part*")
    )
    if len(parts) != 5:
        raise SystemExit(f"Expected 5 qualified artifact parts, found {len(parts)}")

    encoded = "".join(
        "".join(part.read_text(encoding="ascii").split()) for part in parts
    )
    try:
        payload = base64.b64decode(encoded, validate=True)
    except Exception as exc:
        raise SystemExit(f"Qualified artifact base64 decode failed: {exc}")

    if len(payload) != EXPECTED_SIZE:
        raise SystemExit(
            f"Qualified artifact size mismatch: expected {EXPECTED_SIZE}, got {len(payload)}"
        )

    DIST.mkdir(parents=True, exist_ok=True)
    ZIP.write_bytes(payload)

    digest = sha256(ZIP)
    if digest != EXPECTED:
        raise SystemExit(
            "Reconstructed release artifact differs from physically-qualified Candidate 7: "
            f"expected {EXPECTED}, got {digest}"
        )

    with zipfile.ZipFile(ZIP, "r") as zf:
        bad = zf.testzip()
        if bad is not None:
            raise SystemExit(f"Qualified ZIP integrity failed at {bad}")

    SHA.write_text(f"{digest}  {ZIP.name}\n", encoding="utf-8")
    print(ZIP)
    print(SHA)
    print(digest)


if __name__ == "__main__":
    main()
