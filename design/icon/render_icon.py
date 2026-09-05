"""Render Alidade's icon assets at 4x supersample then downsampled with
LANCZOS for clean anti-aliased edges. Produces three files:

- alidade_icon.png            rounded-square, for in-app use (AppBar, README)
- alidade_icon_fullbleed.png  same art, full-bleed square (no pre-rounded
                              corners/transparency) — for the legacy/flat
                              Android launcher icon and iOS, which apply
                              their own mask/rounding.
- alidade_icon_foreground.png glyph only, transparent background, scaled
                              into Android's adaptive-icon safe zone (the
                              center ~66% of the canvas) — the previous
                              icon's "weird white border" was exactly this
                              missing: flutter_launcher_icons was only given
                              the pre-rounded, edge-transparent PNG, so a
                              modern Android launcher's own mask showed its
                              default background through our transparent
                              corners.
"""
import math
from PIL import Image, ImageDraw

SS = 4  # supersample factor
SIZE = 1024 * SS
S = SIZE / 100.0  # px per svg-unit at supersampled res


def _pt(x, y, offset=(0, 0), scale=1.0):
    """Map SVG-space (0-100) coords to supersampled pixel space, with an
    optional recenter (offset, in SVG units) + uniform scale about (50,50)."""
    ox, oy = offset
    xs = (x - 50) * scale + 50 + ox
    ys = (y - 50) * scale + 50 + oy
    return (xs * S, ys * S)


def lerp(a, b, t):
    return a + (b - a) * t


def bg_gradient(size):
    top = (0x1B, 0x1E, 0x29)
    bot = (0x0C, 0x0D, 0x13)
    img = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        img.putpixel((0, y), tuple(int(lerp(top[i], bot[i], t)) for i in range(3)))
    return img.resize((size, size))


def rounded_rect_mask(size, rx):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=rx, fill=255)
    return mask


def thick_line(draw, p0, p1, width, color):
    x0, y0 = p0
    x1, y1 = p1
    draw.line([p0, p1], fill=color, width=int(width))
    r = width / 2
    draw.ellipse([x0 - r, y0 - r, x0 + r, y0 + r], fill=color)
    draw.ellipse([x1 - r, y1 - r, x1 + r, y1 + r], fill=color)


def quad_bezier(p0, p1, p2, n=200):
    pts = []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
        pts.append((x, y))
    return pts


def thick_path(draw, pts, width, color):
    """Draw a smooth stroked ribbon along pts as one filled polygon
    (avoids the seam/hatching artifacts of drawing many short segments)."""
    r = width / 2
    left, right = [], []
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[max(i - 1, 0)]
        x1, y1 = pts[min(i + 1, n - 1)]
        dx, dy = x1 - x0, y1 - y0
        d = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / d, dx / d
        px, py = pts[i]
        left.append((px + nx * r, py + ny * r))
        right.append((px - nx * r, py - ny * r))
    poly = left + right[::-1]
    draw.polygon(poly, fill=color)
    x0, y0 = pts[0]
    x1, y1 = pts[-1]
    draw.ellipse([x0 - r, y0 - r, x0 + r, y0 + r], fill=color)
    draw.ellipse([x1 - r, y1 - r, x1 + r, y1 + r], fill=color)


def star(cx, cy, r_out, r_in=None, rot=0.0):
    """4-point sparkle star polygon centered at (cx, cy)."""
    if r_in is None:
        r_in = r_out * 0.32
    pts = []
    for i in range(8):
        ang = rot + i * math.pi / 4
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    return pts


CREAM = (0xF4, 0xEF, 0xE4, 255)
DARK = (0x0C, 0x0D, 0x13, 255)
GOLD = (0xDB, 0xA8, 0x4E, 255)


def draw_glyph(draw, offset=(0, 0), scale=1.0):
    """Draws the alidade glyph (legs, pivot, gold arc, stars) at the given
    recenter offset / scale, in SVG-space units, onto `draw`."""
    leg_w = 6.5 * S * scale
    thick_line(draw, _pt(50, 26, offset, scale), _pt(29.5, 73, offset, scale), leg_w, CREAM)
    thick_line(draw, _pt(50, 26, offset, scale), _pt(70.5, 73, offset, scale), leg_w, CREAM)

    cx, cy = _pt(50, 26, offset, scale)
    r = 3.2 * S * scale
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=CREAM)
    r2 = 1.1 * S * scale
    draw.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], fill=DARK)

    arc_pts = quad_bezier(
        _pt(26, 74, offset, scale), _pt(50, 89, offset, scale), _pt(74, 74, offset, scale)
    )
    thick_path(draw, arc_pts, 6 * S * scale, GOLD)

    draw.polygon(star(*_pt(76, 25, offset, scale), 9 * S * scale), fill=GOLD)
    draw.polygon(star(*_pt(86.5, 36, offset, scale), 4.4 * S * scale), fill=GOLD)


def render_rounded():
    img = bg_gradient(SIZE).convert("RGBA")
    mask = rounded_rect_mask(SIZE, int(22 * S))
    bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    bg.paste(img, (0, 0), mask)
    draw_glyph(ImageDraw.Draw(bg))
    out = bg.resize((1024, 1024), Image.LANCZOS)
    out.save("alidade_icon.png")
    print("saved alidade_icon.png", out.size)


def render_fullbleed():
    """Full-bleed square: same art, no pre-rounded corners/transparency.
    For legacy Android/iOS launcher icons, which apply their own mask."""
    bg = bg_gradient(SIZE).convert("RGBA")
    draw_glyph(ImageDraw.Draw(bg))
    out = bg.resize((1024, 1024), Image.LANCZOS)
    out.save("alidade_icon_fullbleed.png")
    print("saved alidade_icon_fullbleed.png", out.size)


def render_adaptive_foreground():
    """Glyph only, transparent background, at full scale — flutter_launcher_
    icons applies its own 16% inset for the adaptive-icon safe zone, so the
    source foreground should fill the canvas rather than being pre-shrunk
    (pre-shrinking too, as an earlier version of this script did, doubles
    up the margin and renders a tiny, oddly-placed glyph)."""
    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw_glyph(ImageDraw.Draw(fg))
    out = fg.resize((1024, 1024), Image.LANCZOS)
    out.save("alidade_icon_foreground.png")
    print("saved alidade_icon_foreground.png", out.size)


if __name__ == "__main__":
    render_rounded()
    render_fullbleed()
    render_adaptive_foreground()
