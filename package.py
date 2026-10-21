"""Packs the addon into dist/RaidnightHelper-<version>.zip, with the same
files as the release package: everything in src, plus README.md and
CHANGELOG.md, in a RaidnightHelper folder (see .pkgmeta). The version comes
from the .toc file.

Usage: python package.py
"""
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
ADDON = "RaidnightHelper"  # WoW wants the folder named like the .toc file
EXTRAS = ["README.md", "CHANGELOG.md"]


def version():
    toc = (SRC / f"{ADDON}.toc").read_text(encoding="utf-8")
    match = re.search(r"^## Version:\s*(\S+)", toc, re.MULTILINE)
    if not match:
        raise SystemExit(f"No '## Version:' line in {ADDON}.toc")
    return match.group(1)


def main():
    files = [(path, path.relative_to(SRC).as_posix()) for path in sorted(SRC.rglob("*")) if path.is_file()]
    files += [(ROOT / name, name) for name in EXTRAS]

    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    out = dist / f"{ADDON}-{version()}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for path, name in files:
            zf.write(path, f"{ADDON}/{name}")
    print(f"{out.relative_to(ROOT).as_posix()}: {len(files)} files")


if __name__ == "__main__":
    main()
