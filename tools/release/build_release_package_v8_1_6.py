#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import stat
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
DIST = ROOT / "dist"
NAME = "Reloop_Jockey_3_ME_Bridge_v8_1_6"
ZIP_PATH = DIST / f"{NAME}.zip"
SHA_PATH = DIST / f"{NAME}.zip.sha256"
FIXED_TIME = (2026, 10, 20, 12, 0, 0)

FILES = {
    "README_FIRST.md": ROOT / "docs/RELEASE_PACKAGE_README_v8_1_6.md",
    "RELEASE_NOTES.md": ROOT / "docs/RELEASE_NOTES_v8_0_8_v8_1_6.md",
    "service/install_or_upgrade_reloop_bridge_service_v8_1_6.sh": ROOT / "service/install_or_upgrade_reloop_bridge_service_v8_1_6.sh",
    "service/rollback_to_v8_1_5_from_v8_1_6.sh": ROOT / "service/rollback_to_v8_1_5_from_v8_1_6.sh",
    "service/reloop_bridge_service_status_v8_1_6.sh": ROOT / "service/reloop_bridge_service_status_v8_1_6.sh",
    "service/reloop_reduce_motion_guard_v8_1_6.m": ROOT / "service/reloop_reduce_motion_guard_v8_1_6.m",
}

WRAPPERS = {
    "install_v8_1_6.sh": '#!/bin/bash\nset -e\nHERE="$(cd "$(dirname "$0")" && pwd)"\nexec /bin/bash "$HERE/service/install_or_upgrade_reloop_bridge_service_v8_1_6.sh"\n',
    "rollback_to_v8_1_5.sh": '#!/bin/bash\nset -e\nHERE="$(cd "$(dirname "$0")" && pwd)"\nexec /bin/bash "$HERE/service/rollback_to_v8_1_5_from_v8_1_6.sh"\n',
    "status_v8_1_6.sh": '#!/bin/bash\nset -e\nHERE="$(cd "$(dirname "$0")" && pwd)"\nexec /bin/bash "$HERE/service/reloop_bridge_service_status_v8_1_6.sh"\n',
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def add_bytes(zf: zipfile.ZipFile, arcname: str, data: bytes, mode: int) -> None:
    zi = zipfile.ZipInfo(f"{NAME}/{arcname}", FIXED_TIME)
    zi.create_system = 3
    zi.external_attr = (mode & 0xFFFF) << 16
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data, compresslevel=9)


def main() -> None:
    DIST.mkdir(parents=True, exist_ok=True)
    missing = [str(src) for src in FILES.values() if not src.is_file()]
    if missing:
        raise SystemExit("Missing release inputs:\n" + "\n".join(missing))

    entries: list[tuple[str, bytes, int]] = []
    for arcname, src in FILES.items():
        mode = 0o755 if src.suffix == ".sh" else 0o644
        entries.append((arcname, src.read_bytes(), mode))
    for arcname, content in WRAPPERS.items():
        entries.append((arcname, content.encode("utf-8"), 0o755))

    sums = []
    for arcname, data, _mode in sorted(entries):
        sums.append(f"{hashlib.sha256(data).hexdigest()}  {arcname}")
    entries.append(("SHA256SUMS.txt", ("\n".join(sums) + "\n").encode("utf-8"), 0o644))

    if ZIP_PATH.exists():
        ZIP_PATH.unlink()
    with zipfile.ZipFile(ZIP_PATH, "w") as zf:
        for arcname, data, mode in sorted(entries):
            add_bytes(zf, arcname, data, mode)

    digest = sha256(ZIP_PATH)
    SHA_PATH.write_text(f"{digest}  {ZIP_PATH.name}\n", encoding="utf-8")
    print(ZIP_PATH)
    print(SHA_PATH)
    print(digest)


if __name__ == "__main__":
    main()
