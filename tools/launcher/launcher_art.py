"""Pillow drawing for the MKSM Komplete+ launcher: tiles, the hero banner,
the logo, switches, cards and the app icon. Everything is original art drawn
from code (no game assets). Shapes are drawn at 3x and scaled down, so edges
stay smooth at any Windows display scale."""
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps

SS = 3
IMPACT, SEMIBOLD, REGULAR = "impact.ttf", "seguisb.ttf", "segoeui.ttf"

# the project site's palette
BG = "#0f0f12"
SIDE = "#141418"
CARD = "#1a1a20"
CARD_HI = "#22222a"
LINE = "#2a2a32"
LINE_HI = "#3a3a46"
TEXT = "#f4f4f5"
MUTED = "#a1a1aa"
DIM = "#71717a"
GOLD = "#f5b942"
GOLD_HI = "#ffcb63"
GOLD_DK = "#1a1206"
BLOOD = "#c0392b"
BLOOD_HI = "#dc4632"
GREEN, GREEN_BG = "#5fd39a", "#12291f"
AMBER, AMBER_BG = "#e3b341", "#2a2410"
ORANGE, ORANGE_BG = "#f0975a", "#2c1c10"
BLUE, BLUE_BG = "#7fb2e6", "#12202c"
RED, RED_BG = "#ff8a80", "#2c1414"

_fonts = {}


def font(name, px):
    px = max(4, int(px))
    key = (name, px)
    if key not in _fonts:
        try:
            _fonts[key] = ImageFont.truetype(name, px)
        except OSError:
            _fonts[key] = ImageFont.load_default(px)
    return _fonts[key]


def rgb(color):
    color = color.lstrip("#")
    return tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))


def rgba(color, alpha=255):
    return rgb(color) + (int(alpha),)


def mix(a, b, t):
    ca, cb = rgb(a), rgb(b)
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(ca, cb))


def vgradient(w, h, top, bottom):
    mask = Image.linear_gradient("L").resize((w, h))
    return Image.composite(Image.new("RGBA", (w, h), rgba(bottom)), Image.new("RGBA", (w, h), rgba(top)), mask)


def dgradient(w, h, a, b):
    """a in the top-left corner to b in the bottom-right one."""
    v = Image.linear_gradient("L").resize((w, h))
    hz = Image.linear_gradient("L").rotate(90).transpose(Image.FLIP_LEFT_RIGHT).resize((w, h))
    mask = ImageChops.add(v, hz, scale=2.0)
    return Image.composite(Image.new("RGBA", (w, h), rgba(b)), Image.new("RGBA", (w, h), rgba(a)), mask)


def glow(w, h, color, cx, cy, rx, ry, strength, falloff=1.8):
    """An RGBA layer of soft light: centre (cx, cy) and radii as fractions of the size."""
    # radial_gradient reaches 255 only in its corners (181 mid-edge): stretch it so
    # the light is fully gone at the edges of its box, else the box shows
    m = ImageOps.invert(Image.radial_gradient("L").point(lambda v: min(255, round(v * 255 / 181))))
    m = m.point(lambda v: int(((v / 255) ** falloff) * 255 * strength))
    gw, gh = max(1, int(w * rx * 2)), max(1, int(h * ry * 2))
    m = m.resize((gw, gh))
    alpha = Image.new("L", (w, h), 0)
    alpha.paste(m, (int(w * cx - gw / 2), int(h * cy - gh / 2)))
    layer = Image.new("RGBA", (w, h), rgba(color, 0))
    layer.putalpha(alpha)
    return layer


def rmask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], int(r), fill=255)
    return m


def down(img, w, h):
    return img.resize((max(1, int(w)), max(1, int(h))), Image.LANCZOS)


def fit_font(name, text, max_w, max_h):
    px = int(max_h)
    while px > 6:
        f = font(name, px)
        l, t, r, b = f.getbbox(text)
        if r - l <= max_w and b - t <= max_h:
            return f
        px = int(px * 0.94)
    return font(name, 6)


def glow_text(img, xy, text, fnt, fill, glow_color=None, radius=8, glow_alpha=210, anchor="mm"):
    if glow_color and glow_alpha:
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).text(xy, text, font=fnt, fill=rgba(glow_color, glow_alpha), anchor=anchor)
        img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius)))
    ImageDraw.Draw(img).text(xy, text, font=fnt, fill=rgba(fill) if isinstance(fill, str) else fill, anchor=anchor)


# ------------------------------------------------------------ building blocks
def card(w, h, r, fill, border=None, bg=BG, top=None, border_w=1):
    """A rounded panel (optionally a vertical gradient from `top` to `fill`) on `bg`."""
    W, H = int(w) * SS, int(h) * SS
    # bg None: transparent corners (the fill's colour at alpha 0, so scaling leaves no dark fringe)
    out = Image.new("RGBA", (W, H), rgba(bg) if bg else rgba(fill, 0))
    body = vgradient(W, H, top, fill) if top else Image.new("RGBA", (W, H), rgba(fill))
    out.paste(body, (0, 0), rmask(W, H, r * SS))
    if border:
        ImageDraw.Draw(out).rounded_rectangle([0, 0, W - 1, H - 1], int(r * SS), outline=rgba(border),
                                               width=max(1, int(border_w * SS)))
    return down(out, w, h)


def button(w, h, fill, border=None, bg=BG, top=None, radius=None):
    return card(w, h, radius if radius is not None else h * 0.24, fill, border, bg, top)


def switch(w, h, t, hover=False, bg=CARD, on_color=BLOOD):
    """A toggle switch with its knob at t (0 = off, 1 = on)."""
    W, H = int(w) * SS, int(h) * SS
    out = Image.new("RGBA", (W, H), rgba(bg))
    track = mix("#2e2e38", on_color, t)
    if hover:
        track = mix(track, "#ffffff", 0.08)
    d = ImageDraw.Draw(out)
    d.rounded_rectangle([0, 0, W - 1, H - 1], H // 2, fill=rgba(track),
                        outline=rgba(mix(LINE_HI, on_color, t)), width=SS)
    pad = int(H * 0.16)
    k = H - 2 * pad
    x = pad + (W - 2 * pad - k) * t
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse([x, pad + SS, x + k, pad + k + SS], fill=(0, 0, 0, 110))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(SS * 1.2)))
    ImageDraw.Draw(out).ellipse([x, pad, x + k, pad + k], fill=rgba("#ffffff" if t > 0.5 else "#d4d4d8"))
    return down(out, w, h)


def segments(w, h, count, selected, hover=None, bg=CARD, available=None):
    """The LDK level picker: `count` cells, `selected` gold."""
    W, H = int(w) * SS, int(h) * SS
    out = Image.new("RGBA", (W, H), rgba(bg))
    d = ImageDraw.Draw(out)
    r = int(H * 0.26)
    d.rounded_rectangle([0, 0, W - 1, H - 1], r, fill=rgba("#16161b"), outline=rgba(LINE_HI), width=SS)
    cell = W / count
    for i in range(count):
        x0, x1 = int(i * cell) + 2 * SS, int((i + 1) * cell) - 2 * SS
        if i == selected:
            d.rounded_rectangle([x0, 2 * SS, x1, H - 1 - 2 * SS], r - SS, fill=rgba(GOLD))
        elif i == hover and (available is None or available[i]):
            d.rounded_rectangle([x0, 2 * SS, x1, H - 1 - 2 * SS], r - SS, fill=rgba("#26262e"))
    return down(out, w, h)


# ------------------------------------------------------------ the big pieces
def tile(size, mono, accent, on, selected=False, hover=False, bg=BG, faded=False):
    """A select-screen square: the mod's letters lit in its colour when it's on."""
    W = int(size) * SS
    R = int(size * 0.12) * SS
    body = vgradient(W, W, "#22222b" if hover else "#1c1c23", "#0e0e12")
    body.alpha_composite(glow(W, W, accent, 0.5, 0.40, 0.80, 0.72, 0.95 if on else 0.20, falloff=1.5))
    if selected:
        body.alpha_composite(glow(W, W, GOLD, 0.5, 1.05, 0.9, 0.35, 0.35))
    fnt = fit_font(IMPACT, mono, W * 0.74, W * 0.33)
    fill = TEXT if on else ("#55555f" if not faded else "#45454e")
    glow_text(body, (W / 2, W * 0.41), mono, fnt, fill, accent if on else None, radius=W * 0.045, glow_alpha=235)
    out = Image.new("RGBA", (W, W), rgba(bg))
    out.paste(body, (0, 0), rmask(W, W, R))
    d = ImageDraw.Draw(out)
    border = GOLD if selected else (LINE_HI if hover else "#26262e")
    d.rounded_rectangle([0, 0, W - 1, W - 1], R, outline=rgba(border), width=(2 if selected else 1) * SS)
    return down(out, size, size)


def hero(w, h, bg=BG):
    """The Play page banner: dark gold gradient, a red glow, faint K+ and slashes."""
    S = 2
    W, H = int(w) * S, int(h) * S
    body = dgradient(W, H, "#17171d", "#2a2110")
    body.alpha_composite(glow(W, H, BLOOD, 0.86, 1.05, 0.52, 1.25, 0.85, falloff=1.4))
    body.alpha_composite(glow(W, H, GOLD, 0.06, -0.12, 0.55, 1.1, 0.30, falloff=1.4))
    marks = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(marks)
    d.text((W * 0.84, H * 0.56), "K+", font=font(IMPACT, H * 1.15), fill=rgba(GOLD, 20), anchor="mm")
    for x0, alpha in ((0.585, 46), (0.625, 30), (0.665, 18)):
        d.line([(W * x0, H * 1.08), (W * (x0 + 0.17), -H * 0.08)], fill=rgba(BLOOD, alpha), width=3 * S)
    body.alpha_composite(marks.filter(ImageFilter.GaussianBlur(S * 0.6)))
    out = Image.new("RGBA", (W, H), rgba(bg))
    out.paste(body, (0, 0), rmask(W, H, 16 * S))
    ImageDraw.Draw(out).rounded_rectangle([0, 0, W - 1, H - 1], 16 * S, outline=rgba("#2e2a22"), width=S)
    return down(out, w, h)


def spaced(draw, xy, text, fnt, fill, spacing):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += fnt.getlength(ch) + spacing
    return x


def logo(w, h, bg=SIDE):
    """MKSM over KOMPLETE+, with a red slash under it."""
    W, H = int(w) * SS, int(h) * SS
    out = Image.new("RGBA", (W, H), rgba(bg))
    small = font(IMPACT, H * 0.22)
    spaced(ImageDraw.Draw(out), (0, H * 0.02), "MKSM", small, rgba(MUTED), H * 0.06)
    big = fit_font(IMPACT, "KOMPLETE+", W * 0.98, H * 0.50)
    glow_text(out, (0, H * 0.70), "KOMPLETE+", big, GOLD, BLOOD, radius=H * 0.07, glow_alpha=170, anchor="ls")
    d = ImageDraw.Draw(out)
    width = big.getlength("KOMPLETE+")
    d.polygon([(0, H * 0.82), (width * 0.62, H * 0.82), (width * 0.60, H * 0.88), (0, H * 0.88)], fill=rgba(BLOOD))
    return down(out, w, h)


def coin_button(w, h, glow_t=0.0, hover=False, bg=SIDE, pad=6):
    """The sidebar's gold "insert coin" button, with a coin on the left and a soft
    gold glow around it (glow_t 0..1, pulsed like the site's coin button)."""
    W, H, P = int(w) * SS, int(h) * SS, pad * SS
    out = Image.new("RGBA", (W, H), rgba(bg))
    if glow_t > 0:
        halo = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(halo).rounded_rectangle([P * 0.4, P * 0.4, W - 1 - P * 0.4, H - 1 - P * 0.4],
                                               int((H - 2 * P) * 0.24) + P, fill=rgba(GOLD, int(150 * glow_t)))
        out.alpha_composite(halo.filter(ImageFilter.GaussianBlur(P * 0.45)))
    body_w, body_h = W - 2 * P, H - 2 * P
    top, fill = (mix(GOLD_HI, "#ffffff", 0.18), GOLD_HI) if hover else (GOLD_HI, GOLD)
    body = vgradient(body_w, body_h, top, fill)
    r = int(body_h * 0.24)
    cx, cy, cr = body_h * 0.52, body_h / 2, body_h * 0.30       # the coin
    d = ImageDraw.Draw(body)
    d.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=rgba(GOLD_DK))
    d.ellipse([cx - cr * 0.72, cy - cr * 0.72, cx + cr * 0.72, cy + cr * 0.72], outline=rgba(GOLD), width=SS)
    d.text((cx, cy + SS * 0.5), "+", font=font(IMPACT, cr * 1.25), fill=rgba(GOLD), anchor="mm")
    out.paste(body, (P, P), rmask(body_w, body_h, r))
    return down(out, w, h)


def app_icon(size=256):
    """The window and .exe icon: a gold K+ on a dark rounded square."""
    W = size * SS if size <= 128 else size * 2
    out = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    body = dgradient(W, W, "#24242c", "#0d0d10")
    body.alpha_composite(glow(W, W, BLOOD, 0.5, 0.95, 0.75, 0.55, 0.75))
    fnt = fit_font(IMPACT, "K+", W * 0.80, W * 0.62)
    glow_text(body, (W * 0.5, W * 0.47), "K+", fnt, GOLD, BLOOD, radius=W * 0.035, glow_alpha=220)
    ImageDraw.Draw(body).polygon([(W * 0.18, W * 0.80), (W * 0.82, W * 0.80), (W * 0.80, W * 0.86),
                                  (W * 0.16, W * 0.86)], fill=rgba(BLOOD))
    out.paste(body, (0, 0), rmask(W, W, W * 0.2))
    ImageDraw.Draw(out).rounded_rectangle([0, 0, W - 1, W - 1], int(W * 0.2), outline=rgba("#3a3020"),
                                          width=max(1, W // 64))
    return down(out, size, size)


def save_icon(path):
    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    big = app_icon(256)
    big.save(path, format="ICO", sizes=[(s, s) for s in sizes],
             append_images=[app_icon(s) for s in sizes if s != 256])
