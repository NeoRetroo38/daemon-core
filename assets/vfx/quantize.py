#!/usr/bin/env python3
"""Reduce los PNG de assets/vfx/boot a paleta de 96 colores con alfa (requiere Pillow)."""
import glob
import os
from PIL import Image

for path in sorted(glob.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), "boot", "boot_*.png"))):
    Image.open(path).convert("RGBA").quantize(colors=96, method=Image.Quantize.FASTOCTREE).save(path, optimize=True)
print("ok")
