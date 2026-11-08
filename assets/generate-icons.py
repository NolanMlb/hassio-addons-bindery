#!/usr/bin/env python3
"""Generate the app icon and logo (no third-party dependency).

    python3 assets/generate-icons.py

Writes bindery/icon.png (128x128) and bindery/logo.png (250x100).
Pure stdlib: the shapes are filled with a scanline rasteriser and the result is
supersampled 4x4 for smooth edges.
"""

import math
import os
import struct
import zlib

SS = 4  # supersampling factor per axis

BACKGROUND_TOP = (0x0F, 0x1B, 0x2D)
BACKGROUND_BOTTOM = (0x1B, 0x3B, 0x5C)
PAGE = (0xF7, 0xF9, 0xFC)
PAGE_SHADOW = (0xD3, 0xDD, 0xE9)
RIBBON = (0x35, 0xC7, 0xB0)


class Canvas:
    def __init__(self, width, height):
        self.width = width
        self.height = height
        # RGBA floats, 0..1
        self.pixels = [[(0.0, 0.0, 0.0, 0.0) for _ in range(width)] for _ in range(height)]

    def blend(self, x, y, color, alpha=1.0):
        if alpha <= 0 or not (0 <= x < self.width and 0 <= y < self.height):
            return
        dr, dg, db, da = self.pixels[y][x]
        # colors are defined as 0..255 integers, blended as 0..1 floats
        r, g, b = (channel / 255.0 for channel in color)
        out_a = alpha + da * (1 - alpha)
        if out_a <= 0:
            self.pixels[y][x] = (0.0, 0.0, 0.0, 0.0)
            return
        self.pixels[y][x] = (
            (r * alpha + dr * da * (1 - alpha)) / out_a,
            (g * alpha + dg * da * (1 - alpha)) / out_a,
            (b * alpha + db * da * (1 - alpha)) / out_a,
            out_a,
        )

    def polygon(self, points, color, alpha=1.0):
        ys = [p[1] for p in points]
        y_start = max(0, int(math.floor(min(ys))))
        y_end = min(self.height - 1, int(math.ceil(max(ys))))
        n = len(points)
        for y in range(y_start, y_end + 1):
            cy = y + 0.5
            xs = []
            for i in range(n):
                x1, y1 = points[i]
                x2, y2 = points[(i + 1) % n]
                if y1 == y2:
                    continue
                if (cy >= y1 and cy < y2) or (cy >= y2 and cy < y1):
                    t = (cy - y1) / (y2 - y1)
                    xs.append(x1 + t * (x2 - x1))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                x_from = max(0, int(math.ceil(xs[i] - 0.5)))
                x_to = min(self.width - 1, int(math.floor(xs[i + 1] - 0.5)))
                for x in range(x_from, x_to + 1):
                    self.blend(x, y, color, alpha)

    def rounded_rect(self, x0, y0, x1, y1, radius, color_top, color_bottom):
        for y in range(max(0, y0), min(self.height, y1)):
            cy = y + 0.5
            t = (cy - y0) / max(1, (y1 - y0))
            color = tuple(
                color_top[i] + (color_bottom[i] - color_top[i]) * t for i in range(3)
            )
            for x in range(max(0, x0), min(self.width, x1)):
                cx = x + 0.5
                dx = min(cx - x0, x1 - cx, radius)
                dy = min(cy - y0, y1 - cy, radius)
                if dx >= 0 and dy >= 0 and (dx - radius) ** 2 + (dy - radius) ** 2 <= radius**2:
                    self.blend(x, y, color, 1.0)

    def downsample(self, factor):
        out = Canvas(self.width // factor, self.height // factor)
        for y in range(out.height):
            for x in range(out.width):
                r = g = b = a = 0.0
                for sy in range(factor):
                    for sx in range(factor):
                        pr, pg, pb, pa = self.pixels[y * factor + sy][x * factor + sx]
                        r += pr * pa
                        g += pg * pa
                        b += pb * pa
                        a += pa
                n = factor * factor
                if a > 0:
                    out.pixels[y][x] = (r / a, g / a, b / a, a / n)
                else:
                    out.pixels[y][x] = (0.0, 0.0, 0.0, 0.0)
        return out

    def write_png(self, path):
        raw = bytearray()
        for row in self.pixels:
            raw.append(0)  # filter type 0
            for r, g, b, a in row:
                raw.extend(
                    (
                        max(0, min(255, round(r * 255))),
                        max(0, min(255, round(g * 255))),
                        max(0, min(255, round(b * 255))),
                        max(0, min(255, round(a * 255))),
                    )
                )

        def chunk(tag, data):
            body = tag + data
            return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

        png = b"\x89PNG\r\n\x1a\n"
        png += chunk(b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 6, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        png += chunk(b"IEND", b"")
        with open(path, "wb") as handle:
            handle.write(png)


def draw_book(canvas, ox, oy, scale, width=1.0):
    """Open book centred on (ox, oy), `scale` pixels per unit, 1.0 wide."""
    cx = ox
    w = scale * width
    h = w * 0.62

    def pt(ux, uy):
        return (cx + (ux - 0.5) * w, oy + (uy - 0.5) * h)

    left = [pt(0.02, 0.28), pt(0.47, 0.16), pt(0.47, 0.86), pt(0.02, 0.74)]
    right = [pt(0.53, 0.16), pt(0.98, 0.28), pt(0.98, 0.74), pt(0.53, 0.86)]
    canvas.polygon(left, PAGE)
    canvas.polygon(right, PAGE)

    # spine shadow between the two pages
    canvas.polygon([pt(0.47, 0.16), pt(0.53, 0.16), pt(0.53, 0.86), pt(0.47, 0.86)], PAGE_SHADOW)

    # a ribbon bookmark falling over the right page
    canvas.polygon(
        [pt(0.70, 0.18), pt(0.80, 0.205), pt(0.80, 0.95), pt(0.75, 0.87), pt(0.70, 0.95)],
        RIBBON,
    )


def make_icon(path, size=128):
    canvas = Canvas(size * SS, size * SS)
    pad = int(size * SS * 0.02)
    canvas.rounded_rect(
        pad, pad, size * SS - pad, size * SS - pad,
        radius=int(size * SS * 0.22),
        color_top=BACKGROUND_TOP,
        color_bottom=BACKGROUND_BOTTOM,
    )
    draw_book(canvas, size * SS / 2, size * SS / 2, size * SS * 0.78)
    canvas.downsample(SS).write_png(path)


def make_logo(path, width=250, height=100):
    canvas = Canvas(width * SS, height * SS)
    draw_book(canvas, width * SS / 2, height * SS / 2, height * SS * 0.82)
    canvas.downsample(SS).write_png(path)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    app = os.path.join(os.path.dirname(here), "bindery")
    make_icon(os.path.join(app, "icon.png"))
    make_logo(os.path.join(app, "logo.png"))
    print("wrote", os.path.join(app, "icon.png"))
    print("wrote", os.path.join(app, "logo.png"))
