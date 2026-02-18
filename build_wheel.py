"""
Build a pip-installable wheel from the already-installed qi package.

Usage (after a successful build_all.ps1 run):
    python build_wheel.py

The wheel is written to dist/ and can be installed with:
    pip install dist/qi_windows-4.0.1-cp3XX-cp3XX-win_amd64.whl
"""

import hashlib
import base64
import csv
import io
import os
import re
import sys
import shutil
import struct
import sysconfig
import zipfile
from pathlib import Path

# ── Configuration ─────────────────────────────────────────────────────────

PACKAGE_NAME = "libqi_windows"        # pip install libqi-windows
VERSION      = "4.0.1"               # matches libqi upstream
DESCRIPTION  = "Aldebaran NAOqi (libqi) Python bindings for Windows"
AUTHOR       = "Aldebaran / libqi-windows contributors"
LICENSE      = "BSD-3-Clause"
URL          = "https://github.com/SBelgers/libqi-windows"
REQUIRES_PYTHON = ">=3.11"

# ── Locate the installed qi package ───────────────────────────────────────

def find_qi_dir():
    """Find the qi package in site-packages."""
    site = sysconfig.get_path("purelib")
    qi_dir = Path(site) / "qi"
    if not qi_dir.is_dir():
        sys.exit(f"ERROR: qi package not found at {qi_dir}\n"
                 f"Run build_all.ps1 first to build and install qi.")
    return qi_dir


def wheel_tag():
    """Compute the wheel tag, e.g. cp314-cp314-win_amd64."""
    vi = sys.version_info
    impl = "cp"
    pytag  = f"{impl}{vi.major}{vi.minor}"
    abitag = pytag                     # CPython stable ABI
    if struct.calcsize("P") * 8 == 64:
        plat = "win_amd64"
    else:
        plat = "win32"
    return f"{pytag}-{abitag}-{plat}"


def sha256_b64(data: bytes) -> str:
    """Base64url-encoded SHA-256 digest (no padding) as required by RECORD."""
    digest = hashlib.sha256(data).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")


def build_wheel():
    qi_dir = find_qi_dir()
    tag = wheel_tag()
    dist_info_name = f"{PACKAGE_NAME}-{VERSION}.dist-info"

    dist_dir = Path(__file__).parent / "dist"
    dist_dir.mkdir(exist_ok=True)

    wheel_filename = f"{PACKAGE_NAME}-{VERSION}-{tag}.whl"
    wheel_path = dist_dir / wheel_filename

    print(f"Building wheel: {wheel_filename}")
    print(f"Source: {qi_dir}")

    # Collect all files to include
    files_to_pack = []
    for root, _dirs, filenames in os.walk(qi_dir):
        # Skip __pycache__
        rel_root = Path(root).relative_to(qi_dir.parent)
        if "__pycache__" in rel_root.parts:
            continue
        for fname in filenames:
            full = Path(root) / fname
            arc_name = str(rel_root / fname).replace("\\", "/")
            files_to_pack.append((full, arc_name))

    # Build METADATA
    metadata = (
        f"Metadata-Version: 2.1\n"
        f"Name: {PACKAGE_NAME}\n"
        f"Version: {VERSION}\n"
        f"Summary: {DESCRIPTION}\n"
        f"Author: {AUTHOR}\n"
        f"License: {LICENSE}\n"
        f"Home-page: {URL}\n"
        f"Requires-Python: {REQUIRES_PYTHON}\n"
    )

    # Build WHEEL metadata
    wheel_meta = (
        f"Wheel-Version: 1.0\n"
        f"Generator: libqi-windows-build_wheel\n"
        f"Root-Is-Purelib: false\n"
        f"Tag: {tag}\n"
    )

    # Build top_level.txt
    top_level = "qi\n"

    # Now create the zip (wheel)
    record_lines = []

    with zipfile.ZipFile(wheel_path, "w", zipfile.ZIP_DEFLATED) as whl:
        # Add package files
        for full_path, arc_name in files_to_pack:
            data = full_path.read_bytes()
            whl.writestr(arc_name, data)
            record_lines.append(f"{arc_name},sha256={sha256_b64(data)},{len(data)}")

        # Add dist-info files
        for name, content in [
            ("METADATA", metadata),
            ("WHEEL",    wheel_meta),
            ("top_level.txt", top_level),
        ]:
            arc = f"{dist_info_name}/{name}"
            data = content.encode("utf-8")
            whl.writestr(arc, data)
            record_lines.append(f"{arc},sha256={sha256_b64(data)},{len(data)}")

        # RECORD itself (no hash for itself, per spec)
        record_arc = f"{dist_info_name}/RECORD"
        record_lines.append(f"{record_arc},,")
        record_data = "\n".join(record_lines) + "\n"
        whl.writestr(record_arc, record_data.encode("utf-8"))

    print(f"\nWheel created: {wheel_path}")
    print(f"  Size: {wheel_path.stat().st_size / 1024 / 1024:.1f} MB")
    print(f"  Tag:  {tag}")
    print(f"\nInstall with:")
    print(f"  pip install {wheel_path}")


if __name__ == "__main__":
    build_wheel()
