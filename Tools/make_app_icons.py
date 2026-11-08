#!/usr/bin/env python3
"""Mints the Rea app icon set with nothing but the Python standard library.

Draws a 1024×1024 master (dark slate ground, warm accent tail-curve mark) and
box-downsamples it into every size Xcode expects, writing them straight into
the asset catalog. PNG encoding is hand-rolled on top of zlib.

    python3 Tools/make_app_icons.py           # from the repo root
"""

from __future__ import annotations

import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, "App", "Rea", "Resources", "Assets.xcassets", "AppIcon.appiconset")
MASTER = 1024

# Sizes for a universal iOS icon with the classic (pre-single-size) slot list.
SLOTS = [
    ("iphone", "20x20", "2x", 40),
    ("iphone", "20x20", "3x", 60),
    ("iphone", "29x29", "2x", 58),
    ("iphone", "29x29", "3x", 87),
    ("iphone", "40x40", "2x", 80),
    ("iphone", "40x40", "3x", 120),
    ("iphone", "60x60", "2x", 120),
    ("iphone", "60x60", "3x", 180),
    ("ipad", "20x20", "1x", 20),
    ("ipad", "20x20", "2x", 40),
    ("ipad", "29x29", "1x", 29),
    ("ipad", "29x29", "2x", 58),
    ("ipad", "40x40", "1x", 40),
    ("ipad", "40x40", "2x", 80),
    ("ipad", "76x76", "1x", 76),
    ("ipad", "76x76", "2x", 152),
    ("ipad", "83.5x83.5", "2x", 167),
    ("ios-marketing", "1024x1024", "1x", 1024),
]


def write_png(path: str, width: int, height: int, rgb: bytearray) -> None:
    """Writes an 8-bit RGB PNG from a flat row-major buffer."""
    raw = bytearray()
    stride = width * 3
    for y in range(height):
        raw.append(0)  # filter type 0 (None) per scanline
        raw.extend(rgb[y * stride:(y + 1) * stride])

    def chunk(tag: bytes, payload: bytes) -> bytes:
        body = tag + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", header)
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")

    with open(path, "wb") as handle:
        handle.write(png)


def blend(dst: bytearray, offset: int, color: tuple[int, int, int], alpha: float) -> None:
    a = max(0.0, min(1.0, alpha))
    for channel in range(3):
        base = dst[offset + channel]
        dst[offset + channel] = int(round(base * (1 - a) + color[channel] * a))


def draw_master() -> bytearray:
    """Renders the 1024px master into a flat RGB buffer."""
    buf = bytearray(MASTER * MASTER * 3)
    ground_top = (0x17, 0x1B, 0x22)
    ground_bottom = (0x0A, 0x0C, 0x10)
    accent = (0xFF, 0x8A, 0x3D)
    accent_dim = (0xC9, 0x5F, 0x1E)
    highlight = (0xFF, 0xD8, 0x9C)

    cx = cy = MASTER / 2

    for y in range(MASTER):
        t = y / (MASTER - 1)
        row = (int(ground_top[0] + (ground_bottom[0] - ground_top[0]) * t),
               int(ground_top[1] + (ground_bottom[1] - ground_top[1]) * t),
               int(ground_top[2] + (ground_bottom[2] - ground_top[2]) * t))
        base = y * MASTER * 3
        for x in range(MASTER):
            offset = base + x * 3
            buf[offset] = row[0]
            buf[offset + 1] = row[1]
            buf[offset + 2] = row[2]

    # A soft radial glow behind the mark.
    glow_radius = MASTER * 0.42
    for y in range(int(cy - glow_radius), int(cy + glow_radius)):
        if y < 0 or y >= MASTER:
            continue
        dy = y + 0.5 - cy
        row = y * MASTER * 3
        for x in range(int(cx - glow_radius), int(cx + glow_radius)):
            if x < 0 or x >= MASTER:
                continue
            dx = x + 0.5 - cx
            dist = (dx * dx + dy * dy) ** 0.5
            if dist >= glow_radius:
                continue
            falloff = 1.0 - dist / glow_radius
            blend(buf, row + x * 3, accent_dim, 0.28 * falloff * falloff)

    # The mark: a bold tail curl — two arcs of contrasting weight meeting at a point.
    # Outer arc.
    outer_r = MASTER * 0.30
    inner_r = MASTER * 0.19
    stroke = MASTER * 0.075
    mid_r = (outer_r + inner_r) / 2
    for y in range(MASTER):
        row = y * MASTER * 3
        dy = y + 0.5 - cy
        for x in range(MASTER):
            dx = x + 0.5 - cx
            dist = (dx * dx + dy * dy) ** 0.5
            band = abs(dist - mid_r) - (stroke / 2)
            if band > 1.0:
                continue
            angle = math.atan2(dy, dx)
            # Leave a bite out of the lower-left so it reads as a curl, not a ring.
            if -2.55 < angle < -1.55:
                continue
            # Solid inside the stroke, antialiased across the final pixel.
            coverage = 1.0 if band <= -1.0 else max(0.0, 1.0 - band)
            # Taper the tips by shrinking coverage near the opening.
            edge = min(abs(angle + 2.55), abs(angle + 1.55))
            if edge < 0.22:
                coverage *= edge / 0.22
            blend(buf, row + x * 3, accent, coverage)

    # A warm dot filling the curl's eye.
    eye_r = MASTER * 0.055
    for y in range(int(cy - eye_r), int(cy + eye_r)):
        if y < 0 or y >= MASTER:
            continue
        dy = y + 0.5 - cy
        row = y * MASTER * 3
        for x in range(int(cx - eye_r), int(cx + eye_r)):
            if x < 0 or x >= MASTER:
                continue
            dx = x + 0.5 - cx
            dist = (dx * dx + dy * dy) ** 0.5
            if dist > eye_r + 1:
                continue
            coverage = 1.0 if dist <= eye_r - 1 else max(0.0, eye_r + 1 - dist) / 2
            blend(buf, row + x * 3, highlight, coverage)

    return buf


def downsample(src: bytearray, src_size: int, dst_size: int) -> bytearray:
    """Box filter — average every source block into one destination pixel."""
    if src_size == dst_size:
        return src
    out = bytearray(dst_size * dst_size * 3)
    scale = src_size / dst_size
    for y in range(dst_size):
        y0 = int(y * scale)
        y1 = min(src_size, int((y + 1) * scale))
        if y1 <= y0:
            y1 = y0 + 1
        for x in range(dst_size):
            x0 = int(x * scale)
            x1 = min(src_size, int((x + 1) * scale))
            if x1 <= x0:
                x1 = x0 + 1
            r = g = b = 0
            count = 0
            for sy in range(y0, y1):
                row = sy * src_size * 3
                for sx in range(x0, x1):
                    offset = row + sx * 3
                    r += src[offset]
                    g += src[offset + 1]
                    b += src[offset + 2]
                    count += 1
            offset = (y * dst_size + x) * 3
            out[offset] = r // count
            out[offset + 1] = g // count
            out[offset + 2] = b // count
    return out


def main() -> None:
    os.makedirs(ICON_DIR, exist_ok=True)
    master = draw_master()

    cache: dict[int, bytearray] = {MASTER: master}
    for _, _, _, size in SLOTS:
        if size not in cache:
            cache[size] = downsample(master, MASTER, size)
        filename = f"AppIcon-{size}.png"
        write_png(os.path.join(ICON_DIR, filename), size, size, cache[size])
        print(f"wrote {filename}")


if __name__ == "__main__":
    main()
