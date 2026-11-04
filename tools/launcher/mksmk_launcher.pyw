"""MKSM Komplete+ launcher: install, switch and play the mod pack.

One window for players and testers. It replaces MKSMK.bat's menu and the old
installer window. build_exe.py turns it into a single .exe with the mod
packages inside. From the project folder it also runs as

  pyw -3 tools/launcher/mksmk_launcher.pyw

Pages:
  Play     install or update the set, then play (straight into the game)
  Mods     a tile per mod: details, on/off at once, LDK x2 / x3 / x4
  Tester   routine-script budget, other installed mods, install from a
           folder, QA console, repair, uninstall all
  Credits

Command line (the .exe too):
  --data <folder>   the Recomp's data folder, if it isn't the default (like modtool --data)
  --page <name>     open on play, mods, tester or credits
  --install         no window: Install/Update the set, as the button does, and print what changed
  --report <file>   with --install: also write that text to a file (the .exe has no console)
"""
import argparse, ctypes, os, sys, webbrowser
import tkinter as tk
import tkinter.font as tkfont
from pathlib import Path
from tkinter import filedialog, messagebox

from PIL import Image, ImageTk

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))
import launcher_art as art  # noqa: E402
import launcher_core as core  # noqa: E402
from launcher_art import (AMBER, AMBER_BG, BG, BLOOD, BLOOD_HI, BLUE, BLUE_BG, CARD, DIM, GOLD, GOLD_DK,  # noqa: E402
                          GOLD_HI, GREEN, GREEN_BG, LINE, LINE_HI, MUTED, ORANGE, ORANGE_BG, RED, RED_BG, SIDE, TEXT)

APP = "MKSM Komplete+"
LAUNCHER_VERSION = "1.0.1"
ICON = {"play": "", "mods": "", "tester": "", "credits": "", "folder": "",
        "download": "", "refresh": "", "delete": "", "check": "", "warn": "",
        "info": "", "game": "", "link": "", "settings": "", "error": "",
        "bug": ""}
FONTS = {
    "title": ("Impact", 40), "h1": ("Impact", 26), "h2": ("Segoe UI Semibold", 15),
    "h3": ("Segoe UI Semibold", 11), "lead": ("Segoe UI", 12), "body": ("Segoe UI", 10),
    "body_b": ("Segoe UI Semibold", 10), "small": ("Segoe UI", 9), "kicker": ("Segoe UI Semibold", 8),
    "btn": ("Segoe UI Semibold", 10), "btn_big": ("Impact", 16), "icon": ("Segoe MDL2 Assets", 11),
    "icon_big": ("Segoe MDL2 Assets", 13), "nav": ("Segoe UI Semibold", 11), "tile_name": ("Segoe UI Semibold", 9),
    "tile_state": ("Segoe UI Semibold", 8), "big_num": ("Impact", 30), "section": ("Impact", 15),
    "coin": ("Impact", 14), "small_b": ("Segoe UI Semibold", 9),
}
S = 1.0                                     # display scale (1.0 = 96 dpi)
_KEEP = object()


def px(n):
    return int(round(n * S))


def spaced(text):
    return " ".join(text)


_fontobjs = {}


def fnt(name):
    if name not in _fontobjs:
        _fontobjs[name] = tkfont.Font(font=FONTS[name])
    return _fontobjs[name]


_photos = {}


def photo(key, make):
    """A cached ImageTk.PhotoImage (widgets keep their own reference too)."""
    image = _photos.get(key)
    if image is None:
        if len(_photos) > 600:
            _photos.clear()
        image = _photos[key] = ImageTk.PhotoImage(make())
    return image


# ------------------------------------------------------------------ widgets
class CanvasButton:
    """A button drawn as items on a canvas. Its image is laid over `backdrop`
    (the PIL image under it, e.g. the banner) or over the canvas colour."""
    STYLES = {  # fill, top of gradient, border, text
        "play": (BLOOD, BLOOD_HI, None, "#ffffff"),
        "primary": (GOLD, GOLD_HI, None, GOLD_DK),
        "secondary": ("#202027", "#292931", LINE_HI, TEXT),
        "ghost": (None, None, None, MUTED),
        "danger": (RED_BG, "#361a1a", "#4a2626", RED),
    }

    def __init__(self, canvas, text, command, style="secondary", icon=None, font="btn", padx=16, pady=8,
                 minwidth=0):
        self.c, self.command, self.style, self.text, self.icon = canvas, command, style, text, icon
        self.font, self.padx, self.pady, self.minwidth = font, padx, pady, minwidth
        self.x = self.y = 0
        self.backdrop = None
        self.mode, self.enabled, self.visible = "normal", True, True
        self.tag = f"button{id(self)}"
        self.img = canvas.create_image(0, 0, anchor="nw", tags=self.tag)
        self.ico = canvas.create_text(0, 0, anchor="w", font=FONTS["icon"], state="disabled", tags=self.tag)
        self.lbl = canvas.create_text(0, 0, anchor="w", font=FONTS[font], state="disabled", tags=self.tag)
        canvas.tag_bind(self.img, "<Enter>", lambda e: self._mode("hover"))
        canvas.tag_bind(self.img, "<Leave>", lambda e: self._mode("normal"))
        canvas.tag_bind(self.img, "<ButtonPress-1>", lambda e: self._mode("press"))
        canvas.tag_bind(self.img, "<ButtonRelease-1>", self._release)
        self._measure()

    def _measure(self):
        f = fnt(self.font)
        self.tw = f.measure(self.text)
        self.iw = (fnt("icon").measure(self.icon) + px(8)) if self.icon else 0
        self.w = max(px(self.minwidth), self.tw + self.iw + 2 * px(self.padx))
        self.h = f.metrics("linespace") + 2 * px(self.pady)

    def place(self, x, y, backdrop=None):
        self.x, self.y, self.backdrop = int(x), int(y), backdrop
        self._paint()

    def set(self, text=_KEEP, style=_KEEP, icon=_KEEP, enabled=_KEEP, visible=_KEEP):
        if text is not _KEEP:
            self.text = text
        if style is not _KEEP:
            self.style = style
        if icon is not _KEEP:
            self.icon = icon
        if enabled is not _KEEP:
            self.enabled = enabled
        if visible is not _KEEP:
            self.visible = visible
        self._measure()
        self._paint()

    def _colors(self):
        fill, top, border, color = self.STYLES[self.style]
        if not self.enabled:
            return ("#1c1c22" if fill else None), None, (LINE if fill else None), DIM
        if self.mode == "hover":
            if fill is None:
                return "#24242c", None, None, TEXT
            return art.mix(fill, "#ffffff", 0.10), art.mix(top or fill, "#ffffff", 0.10), border, color
        if self.mode == "press":
            return (art.mix(fill, "#000000", 0.12) if fill else "#1c1c22"), None, border, color
        return fill, top, border, color

    def _paint(self):
        c = self.c
        state = "normal" if self.visible else "hidden"
        for item in (self.img, self.ico, self.lbl):
            c.itemconfigure(item, state=state if item == self.img or state == "hidden" else "disabled")
        if not self.visible:
            return
        fill, top, border, color = self._colors()
        w, h, x, y = self.w, self.h, self.x, self.y
        bg = c.cget("bg")
        backdrop = self.backdrop
        key = ("button", w, h, fill, top, border, bg, id(backdrop) if backdrop is not None else None, x, y)

        def make():
            base = (backdrop.crop((x, y, x + w, y + h)).convert("RGBA") if backdrop is not None
                    else Image.new("RGBA", (w, h), art.rgba(bg)))
            if fill:
                base.alpha_composite(art.button(w, h, fill, border, None, top, radius=h * 0.22))
            return base
        self._ref = photo(key, make)
        c.itemconfigure(self.img, image=self._ref)
        c.coords(self.img, x, y)
        left = x + (w - self.tw - self.iw) / 2
        c.coords(self.ico, left, y + h / 2)
        c.coords(self.lbl, left + self.iw, y + h / 2)
        c.itemconfigure(self.ico, text=self.icon or "", fill=color, disabledfill=color)
        c.itemconfigure(self.lbl, text=self.text, fill=color, disabledfill=color)

    def _mode(self, mode):
        self.mode = mode
        self.c.configure(cursor="hand2" if mode != "normal" and self.enabled else "")
        self._paint()

    def _release(self, e):
        inside = self.x <= self.c.canvasx(e.x) < self.x + self.w and self.y <= self.c.canvasy(e.y) < self.y + self.h
        self._mode("hover" if inside else "normal")
        if inside and self.enabled and self.command:
            self.command()


class Button(tk.Canvas):
    """A button widget on a solid background."""

    def __init__(self, parent, text, command, style="secondary", icon=None, font="btn", padx=14, pady=7,
                 bg=BG, minwidth=0):
        super().__init__(parent, bg=bg, highlightthickness=0, bd=0, width=1, height=1)
        self.cb = CanvasButton(self, text, command, style, icon, font, padx, pady, minwidth)
        self.cb.place(0, 0)
        self.configure(width=self.cb.w, height=self.cb.h)

    def set(self, **kw):
        self.cb.set(**kw)
        self.configure(width=self.cb.w, height=self.cb.h)


class Switch(tk.Canvas):
    W, H = 46, 24

    def __init__(self, parent, command, on=False, bg=CARD):
        super().__init__(parent, width=px(self.W), height=px(self.H), bg=bg, highlightthickness=0, bd=0,
                         cursor="hand2")
        self.command, self.on, self.t, self.hover, self._anim = command, on, 1.0 if on else 0.0, False, None
        self.img = self.create_image(0, 0, anchor="nw")
        self.bind("<Enter>", lambda e: self._hover(True))
        self.bind("<Leave>", lambda e: self._hover(False))
        self.bind("<Button-1>", lambda e: self.command(not self.on))
        self._paint()

    def _hover(self, value):
        self.hover = value
        self._paint()

    def _paint(self):
        t = round(self.t * 4) / 4
        w, h, bg, hover = px(self.W), px(self.H), self.cget("bg"), self.hover
        self._ref = photo(("switch", w, h, t, hover, bg), lambda: art.switch(w, h, t, hover, bg))
        self.itemconfigure(self.img, image=self._ref)

    def set(self, on, animate=True):
        self.on = bool(on)
        target = 1.0 if self.on else 0.0
        if self._anim:
            self.after_cancel(self._anim)
            self._anim = None
        if not animate or self.t == target:
            self.t = target
            self._paint()
            return
        self._step(target)

    def _step(self, target):
        self.t = min(target, self.t + 0.25) if target > self.t else max(target, self.t - 0.25)
        self._paint()
        self._anim = self.after(18, self._step, target) if self.t != target else None


class Segmented(tk.Canvas):
    """The LDK level picker."""

    def __init__(self, parent, command, cell=64, height=32, bg=CARD):
        super().__init__(parent, height=px(height), width=px(cell) * 3, bg=bg, highlightthickness=0, bd=0)
        self.command, self.cell, self.hh = command, cell, height
        self.options, self.selected, self.available, self.hover = [], None, set(), None
        self.img = self.create_image(0, 0, anchor="nw")
        self.bind("<Motion>", self._motion)
        self.bind("<Leave>", lambda e: self._set_hover(None))
        self.bind("<Button-1>", self._click)

    def set(self, options, selected, available):
        self.options, self.selected, self.available = list(options), selected, set(available)
        self.configure(width=px(self.cell) * max(1, len(self.options)))
        self._paint()

    def _index(self, x):
        n = max(1, len(self.options))
        return min(n - 1, max(0, int(x / (px(self.cell)))))

    def _motion(self, e):
        i = self._index(e.x)
        ok = self.options and self.options[i][0] in self.available
        self.configure(cursor="hand2" if ok else "")
        self._set_hover(i)

    def _set_hover(self, i):
        if i != self.hover:
            self.hover = i
            self._paint()

    def _click(self, e):
        if not self.options:
            return
        value = self.options[self._index(e.x)][0]
        if value in self.available and value != self.selected:
            self.command(value)

    def _paint(self):
        self.delete("label")
        n = len(self.options)
        if not n:
            return
        w, h, bg = px(self.cell) * n, px(self.hh), self.cget("bg")
        sel = next((i for i, (v, _) in enumerate(self.options) if v == self.selected), None)
        avail = tuple(v in self.available for v, _ in self.options)
        hover = self.hover
        self._ref = photo(("seg", w, h, n, sel, hover, bg, avail),
                          lambda: art.segments(w, h, n, sel, hover, bg, avail))
        self.itemconfigure(self.img, image=self._ref)
        for i, (value, label) in enumerate(self.options):
            color = GOLD_DK if i == sel else (TEXT if value in self.available else DIM)
            self.create_text(px(self.cell) * (i + 0.5), h / 2, text=label, fill=color, font=FONTS["body_b"],
                             tags="label", state="disabled", disabledfill=color)


class Card(tk.Canvas):
    """A rounded panel; put widgets in .body."""

    def __init__(self, parent, fill=CARD, border=LINE, radius=14, pad=20, bg=BG, top=None, height=None):
        super().__init__(parent, bg=bg, highlightthickness=0, bd=0, width=1, height=px(height) if height else 1)
        self.fill, self.border, self.radius, self.pad, self.top = fill, border, radius, pad, top
        self.body = tk.Frame(self, bg=fill)
        self.bgitem = self.create_image(0, 0, anchor="nw")
        self.win = self.create_window(px(pad), px(pad), anchor="nw", window=self.body)
        self.bind("<Configure>", lambda e: self._render(e.width, e.height))

    def _render(self, w, h):
        if w < 8 or h < 8:
            return
        fill, border, top, r, bg = self.fill, self.border, self.top, px(self.radius), self.cget("bg")
        self._ref = photo(("card", w, h, fill, border, top, r, bg), lambda: art.card(w, h, r, fill, border, bg, top))
        self.itemconfigure(self.bgitem, image=self._ref)
        self.itemconfigure(self.win, width=max(1, w - 2 * px(self.pad)), height=max(1, h - 2 * px(self.pad)))

    def fit(self):
        """Make the card exactly as tall as its content."""
        self.body.update_idletasks()
        self.configure(height=self.body.winfo_reqheight() + 2 * px(self.pad))

    def autofit(self, *wrapping, reserve=0):
        """Keep `wrapping` labels wrapped to the card's width (less `reserve`), and the
        card as tall as its content (for cards that aren't stretched vertically)."""
        def on_configure(e):
            for widget in wrapping:
                widget.configure(wraplength=max(60, e.width - px(4) - reserve))
            self.after_idle(self._refit)
        self.body.bind("<Configure>", on_configure, add="+")
        self.after_idle(self.fit)          # a first height, so the body gets a width to wrap to

    def _refit(self):
        want = self.body.winfo_reqheight() + 2 * px(self.pad)
        if abs(want - self.winfo_height()) > 1:
            self.configure(height=want)


def label(parent, text="", font="body", fg=TEXT, bg=CARD, **kw):
    return tk.Label(parent, text=text, font=FONTS[font], fg=fg, bg=bg, anchor="w", justify="left", bd=0,
                    padx=0, pady=0, **kw)


def textbox(parent, bg=CARD, fg=MUTED, font="body", height=4):
    t = tk.Text(parent, bg=bg, fg=fg, font=FONTS[font], relief="flat", bd=0, highlightthickness=0, wrap="word",
                cursor="arrow", height=height, width=10, padx=0, pady=0, spacing1=px(1), spacing3=px(3),
                insertwidth=0, selectbackground="#3a3a46", selectforeground=TEXT, takefocus=0)
    t.tag_configure("b", foreground=TEXT, font=FONTS["body_b"])
    t.tag_configure("h", foreground=TEXT, font=FONTS["h3"], spacing1=px(8), spacing3=px(4))
    t.tag_configure("section", foreground=GOLD, font=FONTS["section"], spacing1=px(14), spacing3=px(4))
    for name, color in (("gold", GOLD), ("green", GREEN), ("amber", AMBER), ("orange", ORANGE), ("dim", DIM),
                        ("red", RED), ("blue", BLUE), ("muted", MUTED)):
        t.tag_configure(name, foreground=color)
    t.tag_configure("link", foreground=GOLD, underline=True)
    t.tag_bind("link", "<Enter>", lambda e: t.configure(cursor="hand2"))
    t.tag_bind("link", "<Leave>", lambda e: t.configure(cursor="arrow"))
    t.configure(state="disabled")
    return t


def fill_text(t, chunks):
    """chunks: [(text, tags)] or plain strings."""
    t.configure(state="normal")
    t.delete("1.0", "end")
    for chunk in chunks:
        text, tags = (chunk, ()) if isinstance(chunk, str) else chunk
        t.insert("end", text, tags)
    t.configure(state="disabled")


def chips(canvas, items, x=0, y=0, bg=CARD):
    """Draw [(text, fg, bg)] chips left to right on a canvas; returns the x after them."""
    f = fnt("kicker")
    h = f.metrics("linespace") + px(8)
    for text, fg, fill in items:
        w = f.measure(text) + px(16)
        ref = photo(("chip", w, h, fill, bg), lambda w=w, fill=fill: art.card(w, h, h * 0.3, fill, None, bg))
        canvas._refs.append(ref)
        canvas.create_image(x, y, image=ref, anchor="nw")
        canvas.create_text(x + w / 2, y + h / 2, text=text, fill=fg, font=FONTS["kicker"])
        x += w + px(6)
    return x, h


class Toast(tk.Canvas):
    KINDS = {"ok": (GREEN_BG, GREEN, "check"), "warn": (AMBER_BG, AMBER, "warn"), "error": (RED_BG, RED, "error"),
             "info": (BLUE_BG, BLUE, "info")}

    def __init__(self, parent):
        super().__init__(parent, bg=BG, highlightthickness=0, bd=0, cursor="hand2")
        self._timer = None
        self.bind("<Button-1>", lambda e: self.hide())

    def show(self, text, kind="ok", seconds=None):
        fill, color, icon = self.KINDS[kind]
        self.delete("all")
        wrap = px(470)
        probe = self.create_text(0, 0, text=text, font=FONTS["body"], width=wrap, anchor="nw")
        x0, y0, x1, y1 = self.bbox(probe)
        self.delete(probe)
        pad, iw = px(16), px(30)
        w, h = (x1 - x0) + iw + 2 * pad, max(px(48), (y1 - y0) + 2 * px(13))
        self._ref = photo(("toast", w, h, fill), lambda: art.card(w, h, px(12), fill, art.mix(fill, color, 0.35), BG))
        self.create_image(0, 0, image=self._ref, anchor="nw")
        self.create_text(pad, h / 2, text=ICON[icon], font=FONTS["icon_big"], fill=color, anchor="w")
        self.create_text(pad + iw, h / 2, text=text, font=FONTS["body"], fill=TEXT, width=wrap, anchor="w")
        self.place(relx=1.0, rely=1.0, x=-px(26), y=-px(22), anchor="se", width=w, height=h)
        tk.Misc.tkraise(self)            # Canvas.lift raises canvas items, not the widget
        if self._timer:
            self.after_cancel(self._timer)
        seconds = seconds or (9 if kind == "error" else 6)
        self._timer = self.after(int(seconds * 1000), self.hide)

    def hide(self):
        self._timer = None
        self.place_forget()


# ------------------------------------------------------------------ sidebar
class NavItem(tk.Canvas):
    def __init__(self, parent, app, key, text, icon):
        super().__init__(parent, bg=SIDE, highlightthickness=0, bd=0, height=px(44), width=px(236),
                         cursor="hand2")
        self.app, self.key, self.hover = app, key, False
        self.bgrect = self.create_rectangle(0, 0, 0, 0, width=0, fill=SIDE)
        self.bar = self.create_rectangle(0, 0, 0, 0, width=0, fill=GOLD)
        self.ico = self.create_text(px(30), px(22), text=icon, font=FONTS["icon_big"], anchor="w")
        self.lbl = self.create_text(px(62), px(22), text=text, font=FONTS["nav"], anchor="w")
        self.bind("<Enter>", lambda e: self._hover(True))
        self.bind("<Leave>", lambda e: self._hover(False))
        self.bind("<Button-1>", lambda e: app.show(key))
        self.bind("<Configure>", lambda e: self.paint())

    def _hover(self, value):
        self.hover = value
        self.paint()

    def paint(self):
        active = self.app.page == self.key
        w, h = self.winfo_width(), px(44)
        fill = "#1f1f27" if active else ("#1a1a20" if self.hover else SIDE)
        self.coords(self.bgrect, px(12), px(2), w - px(12), h - px(2))
        self.itemconfigure(self.bgrect, fill=fill)
        self.coords(self.bar, px(12), px(10), px(15), h - px(10))
        self.itemconfigure(self.bar, state="normal" if active else "hidden")
        color = TEXT if active else (TEXT if self.hover else MUTED)
        self.itemconfigure(self.ico, fill=GOLD if active else color)
        self.itemconfigure(self.lbl, fill=color)


def animations_on():
    """Windows' "Show animations in Windows" setting; when it's off nothing pulses."""
    if os.name != "nt":
        return True
    value = ctypes.c_int(1)
    try:
        if ctypes.windll.user32.SystemParametersInfoW(0x1042, 0, ctypes.byref(value), 0):  # SPI_GETCLIENTAREAANIMATION
            return bool(value.value)
    except (OSError, AttributeError):
        pass
    return True


class CoinButton(tk.Canvas):
    """The project's support link ("Insert coin: buy me a coffee"), pulsing gently
    like the coin button on the project site."""
    W, H, PAD = 196, 60, 6
    FRAMES = (0.0, 0.2, 0.45, 0.7, 0.9, 1.0, 0.9, 0.7, 0.45, 0.2)

    def __init__(self, parent):
        super().__init__(parent, bg=SIDE, highlightthickness=0, bd=0, width=px(self.W), height=px(self.H),
                         cursor="hand2")
        self.hover, self.frame = False, 0
        self.img = self.create_image(0, 0, anchor="nw")
        x = px(self.PAD) + (px(self.H) - 2 * px(self.PAD))         # right of the coin
        mid = px(self.H) / 2
        top = self.create_text(x, mid + px(1), anchor="sw", text="INSERT COIN", font=FONTS["coin"], fill=GOLD_DK)
        sub = self.create_text(x, mid + px(1), anchor="nw", text="buy me a coffee", font=FONTS["small_b"],
                               fill="#5c3f0c")
        for item in (top, sub):              # Impact's side bearing differs: line both up at x
            self.move(item, x - self.bbox(item)[0], 0)
        self.bind("<Enter>", lambda e: self._hover(True))
        self.bind("<Leave>", lambda e: self._hover(False))
        self.bind("<Button-1>", lambda e: webbrowser.open(core.COFFEE_URL))
        self._paint()
        if animations_on():
            self.after(1500, self._pulse)

    def _hover(self, value):
        self.hover = value
        self._paint()

    def _paint(self):
        t = 0.0 if self.hover else self.FRAMES[self.frame]
        w, h, hover, pad = px(self.W), px(self.H), self.hover, px(self.PAD)
        self._ref = photo(("coin", w, h, t, hover), lambda: art.coin_button(w, h, t, hover, SIDE, pad))
        self.itemconfigure(self.img, image=self._ref)

    def _pulse(self):
        self.frame = (self.frame + 1) % len(self.FRAMES)
        if not self.hover:
            self._paint()
        self.after(220, self._pulse)


class Sidebar(tk.Frame):
    def __init__(self, parent, app):
        super().__init__(parent, bg=SIDE, width=px(236))
        self.app = app
        self.pack_propagate(False)
        logo = tk.Canvas(self, bg=SIDE, highlightthickness=0, bd=0, width=px(184), height=px(74))
        logo.pack(anchor="w", padx=px(26), pady=(px(30), px(4)))
        self._logo = photo(("logo", px(184), px(74)), lambda: art.logo(px(184), px(74), SIDE))
        logo.create_image(0, 0, image=self._logo, anchor="nw")
        title = app.set_title or "mod pack"
        label(self, title, "body_b", TEXT, SIDE).pack(anchor="w", padx=px(28))
        label(self, app.set_date or " ", "small", DIM, SIDE).pack(anchor="w", padx=px(28), pady=(0, px(22)))
        self.items = {}
        for key, text in (("play", "Play"), ("mods", "Mods"), ("tester", "Tester"), ("credits", "Credits")):
            item = NavItem(self, app, key, text, ICON[key])
            item.pack(fill="x")
            self.items[key] = item
        self.status = tk.Canvas(self, bg=SIDE, highlightthickness=0, bd=0, height=px(86))
        self.status.pack(side="bottom", fill="x", padx=px(26), pady=(0, px(22)))
        self.coin = CoinButton(self)
        self.coin.pack(side="bottom", anchor="w", padx=px(20), pady=(0, px(14)))

    def refresh(self):
        for item in self.items.values():
            item.paint()
        app, c = self.app, self.status
        c.delete("all")
        c._refs = []
        lines = []
        lines.append((RED, "Recomp is running") if app.running else
                     ((GREEN, "Game found") if app.game else (ORANGE, "Game not found yet")))
        if app.rows is None:
            lines.append((ORANGE, "No mods folder yet"))
        else:
            on = sum(1 for v in app.views if v.installed and v.on)
            count = core.routine_count(app.rows)
            lines.append((GREEN if on else DIM, f"{on} of {len(app.views)} mods on"))
            lines.append((GREEN if count <= core.ROUTINE_LIMIT else RED, f"{count} of {core.ROUTINE_LIMIT} scripts"))
        for i, (color, text) in enumerate(lines):
            y = i * px(24) + px(10)
            d = px(8)
            ref = photo(("dot", d, color), lambda color=color: art.card(d, d, d / 2, color, None, SIDE))
            c._refs.append(ref)
            c.create_image(0, y - d / 2, image=ref, anchor="nw")
            c.create_text(px(16), y, text=text, fill=MUTED, font=FONTS["small"], anchor="w")


# ------------------------------------------------------------------ pages
class Page(tk.Frame):
    def __init__(self, parent, app):
        super().__init__(parent, bg=BG)
        self.app = app

    def header(self, title, subtitle):
        row = tk.Frame(self, bg=BG)
        row.pack(fill="x", padx=px(34), pady=(px(26), px(16)))
        label(row, title, "h1", TEXT, BG).pack(side="left")
        label(row, subtitle, "body", MUTED, BG).pack(side="left", padx=(px(16), 0), pady=(px(12), 0))
        return row

    def refresh(self):
        pass


class PlayPage(Page):
    def __init__(self, parent, app):
        super().__init__(parent, app)
        self.hero = tk.Canvas(self, bg=BG, highlightthickness=0, bd=0, height=px(262), width=1)
        self.hero.pack(fill="x", padx=px(34), pady=(px(30), px(18)))
        h = self.hero
        self.hero_pil = None
        self.bgitem = h.create_image(0, 0, anchor="nw")
        h.create_text(px(38), px(34), anchor="nw", text=spaced("FREE FAN MOD PACK"), font=FONTS["kicker"], fill=GOLD)
        h.create_text(px(35), px(50), anchor="nw", text="MKSM KOMPLETE+", font=FONTS["title"], fill=TEXT)
        h.create_text(px(38), px(116), anchor="nw", font=FONTS["lead"], fill=MUTED,
                      text="For Mortal Kombat: Shaolin Monks on Shaolin Monks Recomp")
        self.setchip = h.create_text(0, px(36), anchor="ne", font=FONTS["kicker"], fill=MUTED,
                                     text=spaced((app.set_title or "").upper()))
        self.install_btn = CanvasButton(h, "INSTALL", app.install, "primary", ICON["download"], "btn_big", 24, 9, 150)
        self.play_btn = CanvasButton(h, "PLAY", app.play, "play", ICON["play"], "btn_big", 28, 9, 150)
        self.launcher_btn = CanvasButton(h, "Recomp settings", app.open_recomp, "ghost", ICON["settings"], "btn", 12, 7)
        self.ready = h.create_text(0, 0, anchor="w", font=FONTS["body_b"], fill=GREEN, text="")
        self._resize_job = None
        h.bind("<Configure>", self._on_resize)

        cards = tk.Frame(self, bg=BG)
        cards.pack(fill="both", expand=True, padx=px(34), pady=(0, px(30)))
        cards.columnconfigure(0, weight=5, uniform="c")
        cards.columnconfigure(1, weight=6, uniform="c")
        cards.rowconfigure(0, weight=1)
        self.status = Card(cards)
        self.status.grid(row=0, column=0, sticky="nsew", padx=(0, px(9)))
        self.notes = Card(cards)
        self.notes.grid(row=0, column=1, sticky="nsew", padx=(px(9), 0))
        b = self.status.body
        label(b, spaced("YOUR SETUP"), "kicker", DIM).pack(anchor="w")
        self.headline = label(b, "", "h2", TEXT)
        self.headline.pack(anchor="w", pady=(px(4), px(6)))
        self.info = textbox(b)
        self.info.pack(fill="both", expand=True)
        n = self.notes.body
        label(n, spaced(f"WHAT'S IN {app.set_title}".upper().strip()), "kicker", DIM).pack(anchor="w")
        self.notes_text = textbox(n)
        self.notes_text.pack(fill="both", expand=True, pady=(px(8), 0))
        fill_text(self.notes_text, self._note_chunks(app.notes))

    @staticmethod
    def _note_chunks(notes):
        out = []
        for line in (notes or "No release notes in this build.").splitlines():
            if line.startswith("- "):
                head, _, rest = line[2:].partition(": ")
                if rest:
                    out += [("▸ ", "gold"), (head + ": ", "b"), (rest + "\n", ())]
                else:
                    out += [("▸ ", "gold"), (line[2:] + "\n", ())]
            elif line.strip():
                out.append((line + "\n", "muted"))
        return out

    def _on_resize(self, e):
        if self._resize_job:
            self.after_cancel(self._resize_job)
        self._resize_job = self.after(60, self._render_hero)

    def _render_hero(self):
        self._resize_job = None
        w, h = self.hero.winfo_width(), self.hero.winfo_height()
        if w < 50:
            return
        self.hero_pil = art.hero(w, h, BG).convert("RGBA")
        self._hero_ref = ImageTk.PhotoImage(self.hero_pil)
        self.hero.itemconfigure(self.bgitem, image=self._hero_ref)
        self.hero.coords(self.setchip, w - px(30), px(36))
        self._place_buttons()

    def _place_buttons(self):
        if self.hero_pil is None:
            return
        h = self.hero.winfo_height()
        y = h - px(38) - self.play_btn.h
        x = px(38)
        for btn in (self.install_btn, self.play_btn, self.launcher_btn):
            if not btn.visible:
                btn.place(x, y, self.hero_pil)
                continue
            by = y + (self.play_btn.h - btn.h) / 2
            btn.place(x, by, self.hero_pil)
            x += btn.w + px(12)
        self.hero.coords(self.ready, x + px(6), y + self.play_btn.h / 2)

    def refresh(self):
        app = self.app
        pending = app.changes if app.rows is not None else []
        nothing = app.rows is not None and not any(v.installed for v in app.views)
        if app.rows is None:
            self.install_btn.set(visible=False)
        elif pending:
            self.install_btn.set(text="INSTALL" if nothing else "UPDATE", visible=True,
                                 style="primary", icon=ICON["download"])
        else:
            self.install_btn.set(visible=False)
        if app.running:
            self.play_btn.set(text="RUNNING", icon=ICON["game"], enabled=False)
        elif app.game:
            self.play_btn.set(text="PLAY", icon=ICON["play"], enabled=True)
        else:
            self.play_btn.set(text="FIND GAME", icon=ICON["folder"], enabled=True)
        self.launcher_btn.set(visible=bool(app.game))
        self.hero.itemconfigure(self.ready, text=(ICON["check"] + "  Up to date") if (app.rows is not None and
                                                                                      not pending) else "")
        self.hero.itemconfigure(self.ready, font=FONTS["body_b"])
        self._place_buttons()

        chunks = []
        if app.rows is None:
            head = "No mods folder yet"
            chunks.append((app.rows_problem or "", ()))
        elif nothing:
            head = "Not installed yet"
            names = [v.tile.title for v in app.views if v.on]
            chunks += [("Install adds ", ()), (", ".join(names), "b"),
                       (f" (and the rest, switched off). You can switch any of them in Mods.\n", ())]
        elif pending:
            head = f"{len(pending)} change{'s' if len(pending) != 1 else ''} waiting"
            for ch in pending:
                chunks += [("▸ ", "amber"), (ch.text() + "\n", ())]
        else:
            head = "Ready to fight"
            on = sum(1 for v in app.views if v.installed and v.on)
            ldk = next((v for v in app.views if v.is_ldk), None)
            chunks += [(f"{on} of {len(app.views)} mods on", "b")]
            if ldk and ldk.installed:
                chunks += [("  ·  ", "dim"), (f"LDK {ldk.level}" if ldk.on else "LDK off", "b")]
            chunks += [("  ·  ", "dim"), (f"{core.routine_count(app.rows)} of {core.ROUTINE_LIMIT} scripts\n", "b")]
        for v in app.views:
            if v.status == "newer":
                chunks.append((f"{v.tile.title} {v.version} is newer than this set's {v.bundled}, so it stays "
                               "(Tester › Repair puts the set's back).\n", "dim"))
        if app.others:
            names = ", ".join(r["manifest"].get("name", r["id"]) for r in app.others)
            chunks.append((f"Also installed: {names}.\n", "dim"))
        if app.running:
            chunks.append(("Shaolin Monks Recomp is running: close it to install or switch mods.\n", "red"))
        if not app.game:
            chunks.append(("Start the game once from the Recomp so Play can find it, or press Find game.\n", "dim"))
        if app.problems:
            chunks.append(("Skipped packages: " + "; ".join(app.problems) + "\n", "red"))
        self.headline.configure(text=head)
        fill_text(self.info, chunks)


class TileGrid(tk.Canvas):
    COLS = 4

    def __init__(self, parent, app):
        super().__init__(parent, bg=BG, highlightthickness=0, bd=0, width=1, height=1)
        self.app, self.size, self.gap, self.hover = app, px(128), px(14), None
        self.bind("<Motion>", self._motion)
        self.bind("<Leave>", lambda e: self._set_hover(None))
        self.bind("<Button-1>", self._click)
        self.bind("<Double-Button-1>", self._double)

    def layout(self, size):
        self.size = int(size)
        rows = max(1, (len(self.app.views) + self.COLS - 1) // self.COLS)
        self.configure(width=self.COLS * self.size + (self.COLS - 1) * self.gap,
                       height=rows * self.size + (rows - 1) * self.gap + px(2))
        self.draw()

    def cells(self):
        for i, view in enumerate(self.app.views):
            r, c = divmod(i, self.COLS)
            yield view, c * (self.size + self.gap), r * (self.size + self.gap)

    @staticmethod
    def state(view):
        if not view.installed:
            return "NOT INSTALLED", ORANGE
        if view.is_ldk:
            return (f"{(view.level or '').upper()} ON", GOLD) if view.on else ("OFF", DIM)
        return ("ON", GREEN) if view.on else ("OFF", DIM)

    def draw(self):
        self.delete("all")
        self._refs = []
        size = self.size
        for view, x, y in self.cells():
            t = view.tile
            sel, hov, on = t.key == self.app.selected, t.key == self.hover, view.on
            ref = photo(("tile", t.key, size, on, sel, hov),
                        lambda: art.tile(size, t.mono, t.accent, on, sel, hov, BG))
            self._refs.append(ref)
            self.create_image(x, y, image=ref, anchor="nw")
            self.create_text(x + size / 2, y + size * 0.73, text=t.label, font=FONTS["tile_name"],
                             fill=TEXT if on else MUTED, width=size - px(10), justify="center")
            text, color = self.state(view)
            self.create_text(x + size / 2, y + size * 0.875, text=spaced(text), font=FONTS["tile_state"], fill=color)
            dot = {"update": AMBER, "partial": AMBER, "newer": BLUE}.get(view.status) if view.installed else None
            if dot:
                d = px(8)
                ref = photo(("tdot", d, dot), lambda dot=dot: art.card(d, d, d / 2, dot, None, "#1c1c23"))
                self._refs.append(ref)
                self.create_image(x + size - px(16), y + px(10), image=ref, anchor="nw")

    def at(self, ex, ey):
        for view, x, y in self.cells():
            if x <= ex < x + self.size and y <= ey < y + self.size:
                return view
        return None

    def _motion(self, e):
        view = self.at(e.x, e.y)
        self.configure(cursor="hand2" if view else "")
        self._set_hover(view.tile.key if view else None)

    def _set_hover(self, key):
        if key != self.hover:
            self.hover = key
            self.draw()

    def _click(self, e):
        view = self.at(e.x, e.y)
        if view:
            self.app.select(view.tile.key)

    def _double(self, e):
        view = self.at(e.x, e.y)
        if view:
            self.app.toggle(view, not view.on)


class ModsPage(Page):
    def __init__(self, parent, app):
        super().__init__(parent, app)
        self.header("MODS", "Pick a tile for details. Switches take effect right away.")
        self.banner = Card(self, fill=AMBER_BG, border="#4a3d16", pad=14)
        bb = self.banner.body
        self.banner_text = label(bb, "", "body_b", AMBER, AMBER_BG)
        self.banner_text.pack(side="left", fill="x", expand=True)
        self.banner_btn = Button(bb, "Update", app.install, "primary", ICON["download"], bg=AMBER_BG)
        self.banner_btn.pack(side="right", padx=(px(16), 0))
        self.banner.autofit(self.banner_text, reserve=px(140))
        body = tk.Frame(self, bg=BG)
        body.pack(fill="both", expand=True, padx=px(34), pady=(0, px(30)))
        self.body = body
        left = tk.Frame(body, bg=BG)
        left.pack(side="left", fill="y")
        self.grid_canvas = TileGrid(left, app)
        self.grid_canvas.pack(anchor="nw")
        self.legend = tk.Canvas(left, bg=BG, highlightthickness=0, bd=0, height=px(70), width=1)
        self.legend.pack(fill="x", pady=(px(18), 0))
        self.detail = Card(body)
        self.detail.pack(side="left", fill="both", expand=True, padx=(px(22), 0))
        d = self.detail.body
        self.d_kicker = label(d, "", "kicker", DIM)
        self.d_kicker.pack(anchor="w")
        self.d_title = label(d, "", "h2", TEXT)
        self.d_title.pack(anchor="w", pady=(px(2), px(8)))
        self.d_chips = tk.Canvas(d, bg=CARD, highlightthickness=0, bd=0, height=px(24), width=1)
        self.d_chips.pack(fill="x")
        row = tk.Frame(d, bg=CARD)
        row.pack(fill="x", pady=(px(14), px(4)))
        self.d_switch = Switch(row, self._switched)
        self.d_switch.pack(side="left")
        self.d_state = label(row, "", "body_b", TEXT)
        self.d_state.pack(side="left", padx=(px(12), 0))
        self.ldk_row = tk.Frame(d, bg=CARD)
        label(self.ldk_row, "Enemies", "small", DIM).pack(side="left", padx=(0, px(12)))
        self.d_seg = Segmented(self.ldk_row, self._level)
        self.d_seg.pack(side="left")
        self.d_blurb = label(d, "", "body_b", TEXT)
        self.d_blurb.pack(anchor="w", fill="x", pady=(px(12), px(10)))
        tk.Frame(d, bg=LINE, height=1).pack(fill="x", pady=(0, px(10)))
        self.d_text = textbox(d, font="small")
        self.d_text.pack(fill="both", expand=True)
        d.bind("<Configure>", lambda e: self.d_blurb.configure(wraplength=max(100, e.width - px(4))))
        body.bind("<Configure>", self._on_resize)
        self._last_size = None
        self._shown = None

    def draw_legend(self):
        c = self.legend
        c.delete("all")
        c._refs = []
        width = self.grid_canvas.winfo_reqwidth()
        c.configure(width=width)
        c.create_text(0, 0, anchor="nw", width=width, font=FONTS["small"], fill=DIM,
                      text="Double-click a tile or press Space to switch it. Arrow keys move; 2, 3 and 4 pick "
                           "the LDK level.")
        x, d = 0, px(8)
        for color, text in ((AMBER, "update waiting"), (BLUE, "newer than this set")):
            ref = photo(("dot", d, color), lambda color=color: art.card(d, d, d / 2, color, None, BG))
            c._refs.append(ref)
            c.create_image(x, px(48), image=ref, anchor="w")
            item = c.create_text(x + px(14), px(48), anchor="w", font=FONTS["small"], fill=MUTED, text=text)
            x = c.bbox(item)[2] + px(22)

    def _on_resize(self, e):
        gap = px(14)
        avail = e.width * 0.60
        size = max(px(96), min(px(150), (avail - 3 * gap) / 4))
        rows = max(1, (len(self.app.views) + 3) // 4)
        size = min(size, (e.height - (rows - 1) * gap) / rows) if e.height > 50 else size
        size = int(max(px(84), size))
        if size != self._last_size:
            self._last_size = size
            self.grid_canvas.layout(size)
            self.draw_legend()

    def selected(self):
        return next((v for v in self.app.views if v.tile.key == self.app.selected), None) or \
            (self.app.views[0] if self.app.views else None)

    def _switched(self, on):
        view = self.selected()
        if view:
            self.app.toggle(view, on)

    def _level(self, level):
        view = self.selected()
        if view:
            self.app.pick_level(view, level)

    def refresh(self):
        app = self.app
        self.grid_canvas.draw()
        pending = app.changes if app.rows is not None else []
        if app.rows is None:
            self.banner_text.configure(text=app.rows_problem or "No mods folder yet.")
            self.banner_btn.pack_forget()
            show = True
        elif pending:
            nothing = not any(v.installed for v in app.views)
            self.banner_text.configure(text=("Nothing is installed yet. Choose what you want, then install."
                                             if nothing else
                                             f"{len(pending)} change{'s' if len(pending) != 1 else ''} waiting: "
                                             + "; ".join(c.text() for c in pending[:3])
                                             + ("; ..." if len(pending) > 3 else "")))
            self.banner_btn.set(text="Install" if nothing else "Update")
            self.banner_btn.pack(side="right")
            show = True
        else:
            show = False
        if show:
            self.banner.pack(fill="x", padx=px(34), pady=(0, px(16)), before=self.body)
            self.banner.after_idle(self.banner._refit)
        else:
            self.banner.pack_forget()
        view = self.selected()
        if not view:
            return
        t, m = view.tile, view.manifest()
        self.d_kicker.configure(text=spaced(t.mono))
        self.d_title.configure(text=t.title)
        c = self.d_chips
        c.delete("all")
        c._refs = []
        items = [(f"v{view.version}" if view.version else "", TEXT, "#26262e")]
        tag = view.tag
        items.append((tag.upper(), *{"Preview": (AMBER, AMBER_BG), "Diagnostics": (BLUE, BLUE_BG)}.get(
            tag, (GREEN, GREEN_BG))))
        if not view.installed:
            items.append(("NOT INSTALLED", ORANGE, ORANGE_BG))
        elif view.status == "update":
            items.append((f"UPDATE TO {view.bundled}", AMBER, AMBER_BG))
        elif view.status == "partial":
            items.append(("MORE LEVELS IN UPDATE", AMBER, AMBER_BG))
        elif view.status == "newer":
            items.append((f"NEWER THAN SET ({view.bundled})", BLUE, BLUE_BG))
        chips(c, [i for i in items if i[0]])
        self.d_switch.set(view.on, animate=self._shown == t.key)      # no slide when another tile is picked
        self._shown = t.key
        if not view.installed:
            state = "On when installed" if view.on else "Off (installed, switched off)"
        elif view.is_ldk and view.on:
            state = f"On · {core.LEVEL_NAMES.get(view.level, view.level)}"
        else:
            state = "On" if view.on else "Off"
        self.d_state.configure(text=state, fg=TEXT if view.on else MUTED)
        if view.is_ldk:
            options = [(lvl, lvl) for lvl in ("x2", "x3", "x4") if lvl in view.levels]
            self.d_seg.set(options, view.level, view.levels)
            self.ldk_row.pack(fill="x", pady=(px(8), 0), after=self.d_switch.master)
        else:
            self.ldk_row.pack_forget()
        self.d_blurb.configure(text=t.blurb)
        fill_text(self.d_text, [(m.get("summary", ""), ())])


class TesterPage(Page):
    def __init__(self, parent, app):
        super().__init__(parent, app)
        self.header("TESTER", "Tools for playtests and bug reports.")
        body = tk.Frame(self, bg=BG)
        body.pack(fill="both", expand=True, padx=px(34), pady=(0, px(30)))
        body.columnconfigure(0, weight=4, uniform="t")
        body.columnconfigure(1, weight=5, uniform="t")
        body.rowconfigure(1, weight=1)
        self.budget = Card(body)
        self.budget.grid(row=0, column=0, sticky="new", padx=(0, px(9)))
        b = self.budget.body
        label(b, spaced("ROUTINE SCRIPTS"), "kicker", DIM).pack(anchor="w")
        self.count = label(b, "", "big_num", TEXT)
        self.count.pack(anchor="w", pady=(px(2), px(6)))
        self.bar = tk.Canvas(b, bg=CARD, highlightthickness=0, bd=0, height=px(8), width=1)
        self.bar.pack(fill="x")
        self.bar.bind("<Configure>", lambda e: self._paint_bar())
        self.count_note = label(b, "", "small", MUTED)
        self.count_note.pack(anchor="w", fill="x", pady=(px(8), 0))
        self.budget.autofit(self.count_note)
        self.others = Card(body)
        self.others.grid(row=1, column=0, sticky="nsew", padx=(0, px(9)), pady=(px(18), 0))
        label(self.others.body, spaced("OTHER INSTALLED MODS"), "kicker", DIM).pack(anchor="w")
        self.others_list = tk.Frame(self.others.body, bg=CARD)
        self.others_list.pack(fill="both", expand=True, pady=(px(8), 0))
        self.tools = Card(body)
        self.tools.grid(row=0, column=1, rowspan=2, sticky="nsew", padx=(px(9), 0))
        t = self.tools.body
        label(t, spaced("TOOLS"), "kicker", DIM).pack(anchor="w", pady=(0, px(4)))
        folders = self._tool(t, ICON["folder"], "Open a folder", "Mods, session logs, mod backups, or the game.")
        for text, cmd in (("Mods", app.open_mods), ("Logs", app.open_logs), ("Backups", app.open_backups),
                          ("Game", app.open_game)):
            Button(folders, text, cmd, "secondary", padx=10, pady=5).pack(side="left", padx=(0, px(6)))
        row = self._tool(t, ICON["download"], "Install from a folder",
                         "Dev builds or another test set: the newest .tar.xz of each mod in it is installed. "
                         "Other mods stay as they are.")
        Button(row, "Choose folder", app.install_from_folder, "secondary", ICON["folder"]).pack(side="left")
        if core.project_root():
            row = self._tool(t, ICON["bug"], "QA console",
                             "Record a playtest: every save, the logs, live game state and your notes.")
            Button(row, "Open QA console", app.qa_console, "secondary", ICON["bug"]).pack(side="left")
        row = self._tool(t, ICON["refresh"], "Repair",
                         "Reinstall the whole set, even mods that are newer or changed. Switches are kept.")
        Button(row, "Repair", app.repair, "secondary", ICON["refresh"]).pack(side="left")
        row = self._tool(t, ICON["delete"], "Uninstall all",
                         "Remove every mod except language packs. They're moved to the mods backup folder.")
        Button(row, "Uninstall all", app.uninstall_all, "danger", ICON["delete"]).pack(side="left")
        self.sources = label(t, f"Packages: {core.describe_sources(app.sources)}.", "small", DIM)
        self.sources.pack(side="bottom", anchor="w", fill="x")
        t.bind("<Configure>", lambda e: self.sources.configure(wraplength=max(100, e.width - px(4))))

    def _tool(self, parent, icon, title, caption):
        box = tk.Frame(parent, bg=CARD)
        box.pack(fill="x", pady=(px(12), px(2)))
        label(box, icon, "icon_big", GOLD).pack(side="left", anchor="n", padx=(0, px(14)), pady=(px(2), 0))
        col = tk.Frame(box, bg=CARD)
        col.pack(side="left", fill="x", expand=True)
        label(col, title, "h3", TEXT).pack(anchor="w")
        cap = label(col, caption, "small", MUTED)
        cap.pack(anchor="w", fill="x", pady=(px(1), px(8)))
        col.bind("<Configure>", lambda e: cap.configure(wraplength=max(100, e.width - px(4))))
        actions = tk.Frame(col, bg=CARD)
        actions.pack(anchor="w")
        return actions

    def _paint_bar(self):
        c = self.bar
        c.delete("all")
        w, h = c.winfo_width(), px(8)
        rows = self.app.rows or []
        count = core.routine_count(rows)
        ratio = min(1.0, count / core.ROUTINE_LIMIT)
        color = GREEN if ratio < 0.85 else (AMBER if count <= core.ROUTINE_LIMIT else RED)
        c._refs = [photo(("bar", w, h, LINE), lambda: art.card(w, h, h / 2, "#26262e", None, CARD))]
        c.create_image(0, 0, image=c._refs[0], anchor="nw")
        fw = max(h, int(w * ratio))
        if count:
            c._refs.append(photo(("bar", fw, h, color), lambda: art.card(fw, h, h / 2, color, None, "#26262e")))
            c.create_image(0, 0, image=c._refs[1], anchor="nw")

    def refresh(self):
        app = self.app
        rows = app.rows or []
        count = core.routine_count(rows)
        self.count.configure(text=f"{count} / {core.ROUTINE_LIMIT}", fg=RED if count > core.ROUTINE_LIMIT else TEXT)
        self.count_note.configure(text="Routine scripts of the mods that are on. The Recomp doesn't start with "
                                       f"more than {core.ROUTINE_LIMIT}; the MKSMK Probe alone uses 42.")
        self._paint_bar()
        for child in self.others_list.winfo_children():
            child.destroy()
        if not app.others:
            label(self.others_list, "Nothing else is installed.", "small", DIM).pack(anchor="w")
        for row in app.others:
            m = row["manifest"]
            line = tk.Frame(self.others_list, bg=CARD)
            line.pack(fill="x", pady=px(3))
            if m.get("type") == "language":
                label(line, " " + ICON["info"], "icon", BLUE).pack(side="left", padx=(0, px(14)))
            else:
                sw = Switch(line, lambda on, mid=row["id"]: app.switch_other(mid, on), row["enabled"])
                sw.pack(side="left", padx=(0, px(12)))
            label(line, m.get("name", row["id"]), "body_b", TEXT if row["enabled"] else MUTED).pack(side="left")
            label(line, f"  {row['version']}" + ("  ·  language pack" if m.get("type") == "language" else "")
                  + ("  ·  retired, removed by Update" if row["id"] in core.modtool.RETIRED else ""),
                  "small", DIM).pack(side="left")


class CreditsPage(Page):
    def __init__(self, parent, app):
        super().__init__(parent, app)
        self.header("CREDITS", "The people and projects behind the pack.")
        card = Card(self, pad=26)
        card.pack(fill="both", expand=True, padx=px(34), pady=(0, px(30)))
        t = textbox(card.body, font="body")
        t.pack(fill="both", expand=True)
        links = {}

        def link(text, url):
            tag = f"link{len(links)}"
            links[tag] = url
            t.tag_bind(tag, "<Button-1>", lambda e, url=url: webbrowser.open(url))
            return (text, ("link", tag))
        fill_text(t, [
            ("MADE BY\n", "section"),
            ("totallynots8tn", "b"), (": idea, design, direction and QA (every full playthrough).\n", ()),
            ("BUILT ON\n", "section"),
            ("Shaolin Monks Recomp", "b"), (" by ", ()), ("OAleex", "b"),
            (": the PC port this pack runs on, and its routine-mod support. None of this exists without it. ", ()),
            link("github.com/OAleex/ShaolinMonksRecomp", core.RECOMP_URL), ("\n", ()),
            ("WRITTEN WITH\n", "section"),
            ("Claude", "b"), (" (Anthropic, through Claude Code) wrote most of the Lua, the reverse-engineering, the "
                             "tools and the docs. ", ()),
            ("Qwen", "b"), (" (through Qoder) did fenced analysis tasks: QA log and save-file analysis, roster and "
                           "release checks. Nothing ships on an AI's word: hooks need disassembly or memory evidence, "
                           "scripts pass offline tests, and builds are played through in the real game.\n", ()),
            ("INSPIRED BY\n", "section"),
            ("RelaxDirk's UMKSM", "b"), (": the future-roster ideas. Nothing from UMKSM is included, and no "
                                         "affiliation is implied.\n", ()),
            ("SUPPORT\n", "section"),
            link(core.COFFEE_LABEL, core.COFFEE_URL),
            (". Can't chip in? That's fine. Star the repo, share a clip of a 3x fight, or send a bug report. "
             "It all keeps the project alive.\n", ()),
            ("THE PACK\n", "section"),
            ("Free and unofficial. Not affiliated with, endorsed by, or sponsored by Midway, Warner Bros. or "
             "NetherRealm Studios. Mortal Kombat and Shaolin Monks are trademarks of their respective owners. You "
             "need your own legally obtained copy of the game and Shaolin Monks Recomp 0.2.0 or newer; the pack "
             "ships no game files, only original Lua scripts. MIT license.\n", ()),
            link("Project page", core.PROJECT_URL), ("   ·   ", "dim"),
            link("Report a bug", core.PROJECT_URL + "/issues"), ("\n\n", ()),
            (f"Launcher {LAUNCHER_VERSION}  ·  {app.set_title or 'no set'}"
             + (f"  ·  {app.set_date}" if app.set_date else ""), "dim"),
        ])


# ------------------------------------------------------------------ the app
class App(tk.Tk):
    def __init__(self, args):
        super().__init__(className="MKSMKLauncher")
        global S
        S = max(1.0, self.winfo_fpixels("1i") / 96)
        self.args, self.data = args, args.data
        self.title(APP)
        self.configure(bg=BG)
        self._icons = [ImageTk.PhotoImage(art.app_icon(s)) for s in (64, 32, 16)]
        self.iconphoto(True, *self._icons)
        sw, sh = self.winfo_screenwidth(), self.winfo_screenheight()
        w, h = min(px(1160), int(sw * 0.92)), min(px(740), int(sh * 0.88))
        self.geometry(f"{w}x{h}+{max(0, (sw - w) // 2)}+{max(0, (sh - h) // 3)}")
        self.minsize(min(px(1000), w), min(px(640), h))

        self.bundle, self.problems, self.sources = core.load_bundle()
        self.set_title, self.set_date, self.notes = core.set_info(self.sources)
        self.prefs = {"on": {}, "level": "x3"}
        self.rows, self.rows_problem, self.views, self.changes, self.others = None, None, [], [], []
        self.running = core.process_running()
        self.game = core.find_game(self.data)
        self.stamp = None
        self.selected = "ldk"
        self.page = args.page or "play"
        self._ticks = 0

        self.sidebar = Sidebar(self, self)
        self.sidebar.pack(side="left", fill="y")
        tk.Frame(self, bg=LINE, width=1).pack(side="left", fill="y")
        self.main = tk.Frame(self, bg=BG)
        self.main.pack(side="left", fill="both", expand=True)
        self.pages = {"play": PlayPage(self.main, self), "mods": ModsPage(self.main, self),
                      "tester": TesterPage(self.main, self), "credits": CreditsPage(self.main, self)}
        for page in self.pages.values():
            page.place(relx=0, rely=0, relwidth=1, relheight=1)
        self.toast = Toast(self.main)
        for key in ("<Left>", "<Right>", "<Up>", "<Down>", "<space>", "<Return>", "2", "3", "4"):
            self.bind(key, self._key)
        self.reload()
        self.show(self.page)
        self.after(50, self._dark_title_bar)
        self.after(1500, self._poll)

    # ---------------------------------------------------------------- state
    def reload(self):
        self.rows, self.rows_problem = core.read_rows(self.data)
        self.views = core.build_views(self.bundle, self.rows or [], self.prefs)
        self.prefs = core.prefs_from(self.views, self.prefs)
        self.changes = core.plan(self.bundle, self.rows) if self.rows is not None else []
        self.others = core.others(self.bundle, self.rows)
        self.stamp = core.registry_stamp(self.data)
        if self.views and not any(v.tile.key == self.selected for v in self.views):
            self.selected = self.views[0].tile.key
        for page in self.pages.values():
            page.refresh()
        self.sidebar.refresh()

    def _poll(self):
        self._ticks += 1
        running = core.process_running()
        stamp = core.registry_stamp(self.data)
        if self.game is None and self._ticks % 5 == 0:
            self.game = core.find_game(self.data)
            if self.game:
                running = None                      # force a refresh
        if running != self.running or stamp != self.stamp:
            self.running = bool(running) if running is not None else core.process_running()
            self.reload()
        self.after(1500, self._poll)

    def show(self, key):
        self.page = key
        self.pages[key].tkraise()
        tk.Misc.tkraise(self.toast)
        self.sidebar.refresh()

    def select(self, key):
        self.selected = key
        self.pages["mods"].refresh()

    def say(self, text, kind="ok"):
        self.toast.show(text, kind)

    def guard(self, action):
        """Run an action that writes, with a busy cursor; errors become a toast."""
        self.configure(cursor="watch")
        self.update_idletasks()
        try:
            return action()
        except core.ToolError as e:
            self.say(str(e), "error")
        except Exception as e:  # keep the window alive
            self.say(f"Something went wrong: {e}", "error")
        finally:
            self.configure(cursor="")
            self.reload()
        return None

    def _key(self, e):
        if self.page != "mods" or not self.views:
            return
        keys = [v.tile.key for v in self.views]
        i = keys.index(self.selected) if self.selected in keys else 0
        view = self.views[i]
        step = {"Left": -1, "Right": 1, "Up": -TileGrid.COLS, "Down": TileGrid.COLS}.get(e.keysym)
        if step:
            j = i + step
            if 0 <= j < len(keys):
                self.select(keys[j])
        elif e.keysym in ("space", "Return"):
            self.toggle(view, not view.on)
        elif e.char and e.char in "234" and view.is_ldk:
            self.pick_level(view, "x" + e.char)

    # ---------------------------------------------------------------- actions
    def install(self, force=False):
        if self.rows is None:
            self.say(self.rows_problem or "No mods folder yet.", "error")
            return
        if self.running:
            self.say("Close Shaolin Monks Recomp (launcher and game) first.", "error")
            return
        changes = core.plan(self.bundle, self.rows, force)
        if not changes:
            self.say("Everything is up to date.", "ok")
            return
        result = self.guard(lambda: core.install_set(self.data, self.bundle, self.prefs, force))
        if result is None:
            return
        def mods(kinds):        # LDK's three levels count as one mod, as on the tiles
            return len({core.TILE_OF[c.id].key if c.id in core.TILE_OF else c.id
                        for c in result.changes if c.kind in kinds})
        new = mods({"install"})
        other = mods({"update", "reinstall", "downgrade"})
        plural = "s" if new + other != 1 else ""
        text = (f"Installed {new} and updated {other} mods." if new and other else
                f"Installed {new} mod{plural}." if new else f"Updated {other} mod{plural}." if other else "Done.")
        if any(c.kind == "remove" for c in result.changes):
            text += " Retired mods were removed."
        if result.notes:
            text += " " + " ".join(result.notes)
        self.say(text, "warn" if result.notes else "ok")

    def repair(self):
        if self.rows is None:
            self.say(self.rows_problem or "No mods folder yet.", "error")
            return
        changes = core.plan(self.bundle, self.rows, force=True)
        downgrades = [c.text() for c in changes if c.kind == "downgrade"]
        message = f"Reinstall the {len(changes)} mods of {self.set_title or 'the set'}? Switches are kept."
        if downgrades:
            message += "\n\nThis also replaces newer builds:\n" + "\n".join(downgrades)
        if messagebox.askyesno(APP, message, parent=self):
            self.install(force=True)

    def toggle(self, view, on):
        if not view.installed:
            self.prefs["on"][view.tile.key] = bool(on)
            self.reload()
            return
        if self.running:
            self.say("Close Shaolin Monks Recomp first; it reads the switches when it starts.", "error")
            return
        self.guard(lambda: core.switch_tile(self.data, view, on))

    def pick_level(self, view, level):
        self.prefs["level"] = level
        if not view.installed:
            self.prefs["on"]["ldk"] = True
            self.reload()
            return
        if self.running:
            self.say("Close Shaolin Monks Recomp first.", "error")
            return
        if any(core.LEVELS[m] == level for m in view.rows):
            self.guard(lambda: core.switch_tile(self.data, view, True, level))
            return
        # that level isn't installed yet: install just the LDK packages
        self.prefs["on"]["ldk"] = True
        ldk = {m: p for m, p in self.bundle.items() if m in core.LDK_IDS}
        if self.guard(lambda: core.install_set(self.data, ldk, self.prefs)):
            self.say(f"Installed LDK {level} and switched it on.")

    def switch_other(self, mid, on):
        if self.running:
            self.say("Close Shaolin Monks Recomp first.", "error")
            self.reload()
            return
        self.guard(lambda: core.switch(self.data, {mid: on}))

    def play(self):
        if self.running:
            self.say("Shaolin Monks Recomp is already running.", "info")
            return
        if not self.game and not self.locate():
            return
        if self.rows is not None and self.changes:
            nothing = not any(v.installed for v in self.views)
            question = ("The mod pack isn't installed yet. Install it before playing?" if nothing else
                        f"{len(self.changes)} change{'s' if len(self.changes) != 1 else ''} waiting. "
                        "Install them before playing?")
            answer = messagebox.askyesnocancel(APP, question, parent=self)
            if answer is None:
                return
            if answer:
                self.install()
                if core.plan(self.bundle, core.read_rows(self.data)[0] or []):
                    return                          # the install failed; its toast says why
        self._start(direct=core.game_ready(self.data))

    def open_recomp(self):
        if self.running:
            self.say("Shaolin Monks Recomp is already running.", "info")
            return
        if self.game or self.locate():
            self._start(direct=False)

    def _start(self, direct):
        try:
            core.launch_game(self.game, direct=direct)
        except OSError as e:
            self.say(f"Couldn't start the game: {e}", "error")
            return
        self.after(700, self.destroy)

    def locate(self):
        path = filedialog.askopenfilename(parent=self, title="Find ShaolinMonksRecomp.exe",
                                          filetypes=[("Shaolin Monks Recomp", core.PROCESS), ("Programs", "*.exe")])
        if not path:
            return False
        settings = core.load_settings()
        settings["game_exe"] = path
        core.save_settings(settings)
        self.game = Path(path)
        self.reload()
        return True

    def _open(self, path):
        try:
            core.open_path(path)
        except (core.ToolError, OSError) as e:
            self.say(str(e), "warn")

    def open_mods(self):
        self._open(core.data_folder(self.data) / "mods")

    def open_logs(self):
        self._open(core.data_folder(self.data) / "logs")

    def open_backups(self):
        self._open(core.data_folder(self.data) / "mods" / ".mksmk-backup")

    def open_game(self):
        if self.game or self.locate():
            self._open(self.game.parent)

    def install_from_folder(self):
        folder = filedialog.askdirectory(parent=self, title="Folder with mod packages (.tar.xz)")
        if not folder:
            return
        result = self.guard(lambda: core.install_folder(self.data, folder, self.prefs))
        if result:
            names = ", ".join(f"{c.name} {c.new}" for c in result.changes)
            self.say(f"Installed {names}." + (" " + " ".join(result.notes) if result.notes else ""),
                     "warn" if result.notes else "ok")

    def qa_console(self):
        root = core.project_root()
        try:
            core.open_qa_console(root)
            self.say("QA console opened (it starts minimized). Press Start recording there, then play.", "info")
        except (core.ToolError, OSError) as e:
            self.say(str(e), "error")

    def uninstall_all(self):
        if not messagebox.askyesno(APP, "Uninstall every mod? Language packs stay, and removed mods go to the "
                                        "mods backup folder.", parent=self):
            return
        removed = self.guard(lambda: core.uninstall_all(self.data))
        if removed is not None:
            self.say(f"Removed {len(removed)} mod{'s' if len(removed) != 1 else ''}." if removed else
                     "Nothing to remove.")

    # ---------------------------------------------------------------- window
    def _dark_title_bar(self):
        if os.name != "nt":
            return
        try:
            hwnd = ctypes.windll.user32.GetParent(self.winfo_id())
            dark = ctypes.c_int(1)
            for attribute in (20, 19):          # DWMWA_USE_IMMERSIVE_DARK_MODE (and its old number)
                if ctypes.windll.dwmapi.DwmSetWindowAttribute(hwnd, attribute, ctypes.byref(dark), 4) == 0:
                    break
            r, g, b = art.rgb(SIDE)
            color = ctypes.c_int(r | (g << 8) | (b << 16))
            ctypes.windll.dwmapi.DwmSetWindowAttribute(hwnd, 35, ctypes.byref(color), 4)   # caption colour (Win 11)
        except (OSError, AttributeError):
            pass

    def screenshot(self, path, delay=1600):
        """Developer aid: save a picture of the window, then close."""
        def grab():
            from PIL import ImageGrab
            self.attributes("-topmost", True)
            self.update()
            x, y = self.winfo_rootx(), self.winfo_rooty()
            w, h = self.winfo_width(), self.winfo_height()
            ImageGrab.grab(bbox=(x, y, x + w, y + h), all_screens=True).save(path)
            self.destroy()
        self.after(delay, grab)


# ------------------------------------------------------------------ entry
def headless_install(args):
    bundle, problems, sources = core.load_bundle()
    out = [f"Packages: {core.describe_sources(sources)}"]
    out += [f"skipped: {p}" for p in problems]
    rows, problem = core.read_rows(args.data)
    code = 0
    if rows is None:
        out.append("Error: " + problem)
        code = 1
    else:
        prefs = core.prefs_from(core.build_views(bundle, rows, {}), {})
        try:
            result = core.install_set(args.data, bundle, prefs)
            out += [c.text() for c in result.changes] or ["Everything is up to date."]
            out += ["Note: " + n for n in result.notes]
            out += ["", "Now installed:", core.modtool.describe(result.rows)]
            if result.backup and any(c.kind != "install" for c in result.changes):
                out.append(f"\nRemoved/replaced files were moved to {result.backup}")
        except core.ToolError as e:
            out.append("Error: " + str(e))
            code = 1
    text = "\n".join(out)
    print(text)
    if args.report:
        Path(args.report).write_text(text + "\n", encoding="utf-8")
    return code


def main(argv=None):
    parser = argparse.ArgumentParser(prog="MKSM Komplete+", description="MKSM Komplete+ launcher")
    parser.add_argument("--data", help="the Recomp's data folder (default: %%LOCALAPPDATA%%\\Shaolin Monks Recomp)")
    parser.add_argument("--page", choices=("play", "mods", "tester", "credits"))
    parser.add_argument("--install", action="store_true", help="Install/Update the set without a window")
    parser.add_argument("--report", help="with --install: also write the result to this file")
    parser.add_argument("--select", help=argparse.SUPPRESS)          # developer: tile to select
    parser.add_argument("--screenshot", help=argparse.SUPPRESS)      # developer: save a picture and close
    args = parser.parse_args(argv)
    if args.install:
        return headless_install(args)
    if os.name == "nt":
        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except (OSError, AttributeError):
            pass
        try:
            ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("MKSMK.KompletePlus.Launcher")
        except (OSError, AttributeError):
            pass
    app = App(args)
    if args.select:
        app.select(args.select)
    if args.screenshot:
        app.screenshot(args.screenshot)
    app.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
