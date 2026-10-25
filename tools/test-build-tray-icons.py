#!/usr/bin/env python3
"""Smoke-test CorelDRAW SVG conversion without touching repo assets."""
import base64
import runpy
import shutil
import tempfile
from io import BytesIO
from pathlib import Path

from PIL import Image

root = Path(__file__).resolve().parents[1]
source_svg = root / "assets" / "u_logo_tempg2.svg"
if not source_svg.is_file():
    raise RuntimeError("Official CorelDRAW reference SVG missing")
builder = runpy.run_path(str(root / "tools" / "build-tray-icons.py"))["build"]
with tempfile.TemporaryDirectory(prefix="utg-render-test-") as location:
    base = Path(location)
    source = base / "logo"
    destination = base / "out"
    source.mkdir()
    shutil.copyfile(source_svg, source / "utg_w_000.svg")
    count = builder(source, destination)
    if count != 1:
        raise AssertionError(f"Expected 1 frame, got {count}")
    raster = destination / "utg_w_000.png.base64"
    png = base64.b64decode(raster.read_text(encoding="ascii").strip(), validate=True)
    with Image.open(BytesIO(png)) as img:
        if img.size != (64, 64) or img.mode not in {"RGBA", "RGB"}:
            raise AssertionError(f"Wrong output size or colorspace: {img.size}, {img.mode}")
        if img.getbbox() is None:
            raise AssertionError("Blank image")
    if not source_svg.read_bytes() == (source / "utg_w_000.svg").read_bytes():
        raise AssertionError("Original reference SVG changed")
print("PASS: 64px PNG rasterization from user CorelDRAW SVG, without changing the source")
