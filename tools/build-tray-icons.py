#!/usr/bin/env python3
"""Render user-owned CorelDRAW SVGs to deterministic 64px tray frames.

Source SVGs stay untouched. Generated base64 text loads in Windows PowerShell 5.1,
which cannot render SVG natively. Requires: pip install cairosvg
"""
from __future__ import annotations

import argparse
import base64
import io
import re
from pathlib import Path

ICON = re.compile(r"^utg_[wb]_(?:000|010|020|030|040|050|060|070|080|090|100)(?:_active)?$")
ACTIVE = re.compile(r"^utg_[wb]_(?:080|090|100)_active$")
MAX_SVG_BYTES = 2_000_000


def build(source: Path, destination: Path) -> int:
    import cairosvg
    from PIL import Image

    icons = sorted(source.glob("utg_*.svg"))
    expected_names = [p for p in icons if ICON.fullmatch(p.stem)]
    destination.mkdir(parents=True, exist_ok=True)
    if not expected_names:
        print(f"No user SVG icon frames yet in {source}; keeping fallback official logo.")
        return 0

    output: dict[str, str] = {}
    for path in expected_names:
        if path.stem.endswith("_active") and not ACTIVE.fullmatch(path.stem):
            raise ValueError(f"Active frames are allowed only for 080/090/100: {path.name}")
        if path.stat().st_size > MAX_SVG_BYTES:
            raise ValueError(f"SVG file exceeds 2 MB: {path.name}")
        raw = path.read_bytes()
        # Avoid fetching remote dependencies when rasterizing user-controlled assets.
        if re.search(rb"(?:https?:)?//", raw, re.IGNORECASE) and re.search(
            rb"(?:href|url\s*\()\s*['\"]?\s*(?:https?:)?//", raw, re.IGNORECASE
        ):
            raise ValueError(f"Remote image/font references are not supported: {path.name}")
        png = cairosvg.svg2png(bytestring=raw, output_width=64, output_height=64)
        with Image.open(io.BytesIO(png)) as image:
            if image.size != (64, 64):
                raise ValueError(f"Unexpected raster size for {path.name}")
            if image.getbbox() is None:
                raise ValueError(f"Blank SVG icon: {path.name}")
        output[path.stem + ".png.base64"] = base64.b64encode(png).decode("ascii") + "\n"

    destination.mkdir(parents=True, exist_ok=True)
    for old in destination.glob("utg_*.png.base64"):
        if old.name not in output:
            old.unlink()
    for filename, data in output.items():
        (destination / filename).write_text(data, encoding="ascii", newline="\n")
    print(f"Rendered {len(output)} SVG frames at 64x64; preserved original SVG files.")
    return len(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path("assets/logo"))
    parser.add_argument("--dest", type=Path, default=Path("assets/tray-icons"))
    args = parser.parse_args()
    build(args.source, args.dest)


if __name__ == "__main__":
    main()
