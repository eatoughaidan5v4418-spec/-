#!/usr/bin/env python3
"""Export the picture resources of the serial screen from the HTML prototype.

Renders docs/串口屏界面_v1/界面原型.html in a headless browser at 480x272, puts the
page into each needed state and crops the control rectangles.

Output (docs/串口屏界面_v1/):
    素材/NN_name.png   93 pictures, NN = picture id used by the firmware (hmi_res.h)
    素材预览.png        contact sheet
    控件坐标.md         control rectangles measured from the prototype

Needs: pip install playwright pillow   (uses the installed Edge or Chrome, no download)
Run:   py tools/export_hmi_assets.py
"""
import io
import os
import sys

from PIL import Image, ImageChops, ImageDraw
from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "docs", "串口屏界面_v1")
PROTO = os.path.join(DOC, "界面原型.html")
OUT = os.path.join(DOC, "素材")
W, H = 480, 272

DIRS = ["E", "NE", "N", "NW", "W", "SW", "S", "SE"]
# Fixed rectangles (x, y, w, h). They must not overlap each other: see README section 3.2.
BAY_RECT = {
    "E": (191, 113, 64, 46), "NE": (159, 36, 77, 77), "N": (113, 17, 46, 64), "NW": (36, 36, 77, 77),
    "W": (17, 113, 64, 46), "SW": (36, 159, 77, 77), "S": (113, 191, 46, 74), "SE": (159, 159, 77, 77),
}
HUB_RECT = (98, 98, 76, 76)
PANEL_RECT = (273, 33, 207, 239)
BTN_PAD = 4         # keep a little of the glow around buttons

MAIN_DYN = ["tClk", "tabs", "nFree", "tTot", "jOcc", "bStore", "tSel", "bGet", "pTray", "pHand",
            "bOk", "bCancel", "bTaken", "tJob", "tStep", "tIdx", "jStep", "nEta"]
FAULT_DYN = ["tClk", "tCode", "tTitle", "tDesc", "c0", "c1", "bHome"]

HOME = "go('home');S.layers=2;S.layer=1;S.lift=0;S.fx=null;S.sel=null;"
ALL = "for(const l of [1,2])for(const d of DIRS)if(S.bay[l][d]!==-1)S.bay[l][d]=%d;"
DEFAULT_BAYS = ("S.bay={1:{E:2,NE:1,N:2,NW:1,W:1,SW:2,S:1,SE:1},"
                "2:{E:1,NE:1,N:2,NW:1,W:1,SW:1,S:-1,SE:1}};")


class Shooter:
    def __init__(self, page):
        self.page = page
        self.rects = {}             # (page name, control) -> (x, y, w, h)

    def shot(self, js, hide=()):
        css = "".join('[data-ctl="%s"]{visibility:hidden!important}' % n for n in hide)
        self.page.evaluate(
            "([js, css]) => { clearInterval(tm); (0, eval)(js); draw();"
            " document.getElementById('exportcss').textContent = css; }", [js, css])
        png = self.page.screenshot(clip={"x": 0, "y": 0, "width": W, "height": H})
        return Image.open(io.BytesIO(png)).convert("RGB")

    def rect(self, name, pad=0):
        r = self.page.evaluate(
            "(n) => { const e = [...document.querySelectorAll('[data-ctl=\"' + n + '\"]')]"
            ".find(x => x.offsetParent !== null); if (!e) return null;"
            " const b = e.getBoundingClientRect(); return [b.left, b.top, b.right, b.bottom]; }", name)
        if r is None:
            sys.exit("control %s is not on the page" % name)
        x0, y0 = int(r[0] // 1) - pad, int(r[1] // 1) - pad
        x1, y1 = int(-(-r[2] // 1)) + pad, int(-(-r[3] // 1)) + pad
        return (x0, y0, x1 - x0, y1 - y0)


def visible_diff(a, b):
    """Mask of pixels that differ by more than one RGB565 step (ignores anti-aliasing noise)."""
    return ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 8 else 0)


def count(mask):
    return mask.histogram()[255]


def crop(img, r):
    return img.crop((r[0], r[1], r[0] + r[2], r[1] + r[3]))


def main():
    pics = {}                       # id -> (name, image)
    rects = {}                      # (page, control) -> rect

    def put(pid, name, img):
        if pid in pics:
            sys.exit("picture id %d used twice" % pid)
        pics[pid] = (name, img)

    with sync_playwright() as pw:
        browser = None
        for channel in ("msedge", "chrome"):
            try:
                browser = pw.chromium.launch(channel=channel, headless=True, args=["--disable-lcd-text"])
                break
            except Exception:
                continue
        if browser is None:
            sys.exit("no Edge or Chrome found for playwright")
        page = browser.new_page(viewport={"width": W, "height": H}, device_scale_factor=1)
        page.goto("file:///" + PROTO.replace("\\", "/"))
        page.evaluate("document.body.classList.add('export');"
                      "const s=document.createElement('style');s.id='exportcss';document.head.appendChild(s);")
        sh = Shooter(page)

        # ---- main page: background, panels -------------------------------------------
        put(0, "bg_main", sh.shot(HOME + "S.fx='none';", MAIN_DYN))
        put(3, "panel_home", crop(sh.shot(HOME, MAIN_DYN), PANEL_RECT))
        put(4, "panel_sel", crop(sh.shot(HOME + "S.sel={l:1,d:'N'};", MAIN_DYN), PANEL_RECT))
        dock = HOME + "S.job={kind:'%s',l:1,d:'NE',hand:%d,notray:%d};S.page='dock';"
        put(5, "panel_dock_put", crop(sh.shot(dock % ("store", 0, 0), MAIN_DYN), PANEL_RECT))
        put(6, "panel_dock_take", crop(sh.shot(dock % ("get", 0, 0), MAIN_DYN), PANEL_RECT))
        prog = HOME + "S.job={kind:'store',l:1,d:'NE',steps:['-','-'],i:0};S.page='prog';"
        put(7, "panel_prog", crop(sh.shot(prog, MAIN_DYN), PANEL_RECT))

        # ---- bay sprites ---------------------------------------------------------------
        f_empty = sh.shot(HOME + ALL % 0)
        f_tray = sh.shot(HOME + ALL % 1)
        f_car = sh.shot(HOME + ALL % 2 + "S.bay[1].S=1;")
        # Selected / target bays glow, so render them one at a time: otherwise the glow of
        # the neighbours ends up in the corners of each sprite.
        f_sel = {d: sh.shot(HOME + ALL % 1 + "S.bay[1].%s=2;S.sel={l:1,d:'%s'};" % (d, d)) for d in DIRS if d != "S"}
        f_tgt = {d: sh.shot(HOME + ALL % 1 + "S.job={kind:'store',l:1,d:'%s',steps:['-'],i:0};S.page='prog';" % d)
                 for d in DIRS}
        f_dock = sh.shot(HOME + ALL % 1 + "S.job={kind:'store',l:1,d:'NE',hand:0};S.page='dock';")
        f_l2 = sh.shot(HOME + ALL % 1 + "S.layer=2;")
        state_names = ["empty", "tray", "car", "sel", "target"]
        for di, d in enumerate(DIRS):
            frames = [f_empty, f_tray, f_car, f_sel.get(d), f_tgt[d]]
            names = list(state_names)
            if d == "S":
                frames[2], names[2] = f_dock, "dock_active"
                frames[3], names[3] = f_l2, "shaft"
                names[0], names[1], names[4] = "dock_empty", "dock_tray", "dock_target"
            for st in range(5):
                put(8 + di * 5 + st, "bay_%s_%s" % (d, names[st]), crop(frames[st], BAY_RECT[d]))

        # Everything that changes with the bay state must be inside the bay rectangles.
        mask = Image.new("L", (W, H), 255)
        for r in BAY_RECT.values():
            ImageDraw.Draw(mask).rectangle((r[0], r[1], r[0] + r[2] - 1, r[1] + r[3] - 1), fill=0)
        mask.paste(0, (272, 0, W, H))
        # The tick ring (radius >= 124) is static; its anti-aliasing varies by a few levels
        # between renders, so leave it out of the check.
        ring = Image.new("L", (W, H), 0)
        ImageDraw.Draw(ring).ellipse((136 - 123, 136 - 123, 136 + 123, 136 + 123), fill=255)
        mask = ImageChops.multiply(mask, ring)
        leaks = {}
        for name, f in (("tray", f_tray), ("car", f_car)):
            leaks[name] = count(ImageChops.multiply(visible_diff(f, f_empty), mask))
        # Glow that falls outside the sprite is simply not shown on the real screen.
        leaks["sel glow cut off"] = sum(count(ImageChops.multiply(visible_diff(f, f_tray), mask)) for f in f_sel.values())
        leaks["target glow cut off"] = sum(count(ImageChops.multiply(visible_diff(f, f_tray), mask)) for f in f_tgt.values())

        # ---- hub -----------------------------------------------------------------------
        for di, d in enumerate(DIRS):
            put(48 + di, "hub_%s" % d, crop(sh.shot(HOME + "S.lift=1;S.head='%s';" % d), HUB_RECT))
        put(56, "hub_none", crop(sh.shot(HOME), HUB_RECT))

        # ---- tabs, home panel controls ----------------------------------------------------
        f = sh.shot(HOME + DEFAULT_BAYS)
        for n in ("tClk", "nFree", "tTot", "jOcc"):
            rects[("main", n)] = sh.rect(n)
        # The two tab controls are the left and right half of the tab strip.
        tx, ty, tw, th = sh.rect("tabs")
        rects[("main", "tab1")] = (tx, ty, tw // 2, th)
        rects[("main", "tab2")] = (tx + tw // 2, ty, tw - tw // 2, th)
        rects[("main", "bStore")] = sh.rect("bStore", BTN_PAD)
        put(57, "tab1_on", crop(f, rects[("main", "tab1")]))
        put(60, "tab2_off", crop(f, rects[("main", "tab2")]))
        put(61, "btn_store", crop(f, rects[("main", "bStore")]))
        down = "document.querySelector('[data-ctl=\"%s\"]').classList.add('down');"
        off = "{const e=document.querySelector('[data-ctl=\"%s\"]');e.classList.remove('pri');e.classList.add('off');}"

        def variant(js, name, extra):
            # draw() rebuilds the DOM, so the class tweak has to run after it.
            sh.shot(js)
            sh.page.evaluate(extra % name)
            png = sh.page.screenshot(clip={"x": 0, "y": 0, "width": W, "height": H})
            return Image.open(io.BytesIO(png)).convert("RGB")

        put(62, "btn_store_down", crop(variant(HOME + DEFAULT_BAYS, "bStore", down), rects[("main", "bStore")]))
        put(63, "btn_store_off", crop(variant(HOME + DEFAULT_BAYS, "bStore", off), rects[("main", "bStore")]))
        f = sh.shot(HOME + "S.layer=2;")
        put(58, "tab1_off", crop(f, rects[("main", "tab1")]))
        put(59, "tab2_on", crop(f, rects[("main", "tab2")]))

        occ = rects[("main", "jOcc")]
        put(85, "occ14_empty", crop(sh.shot(HOME + ALL % 1), occ))
        put(86, "occ14_full", crop(sh.shot(HOME + ALL % 2), occ))
        # One layer: the prototype moves the panel up (no tabs), so measure the bar again.
        f = sh.shot(HOME + ALL % 1 + "S.layers=1;")
        occ7 = sh.rect("jOcc")
        put(87, "occ7_empty", crop(f, occ7))
        put(88, "occ7_full", crop(sh.shot(HOME + ALL % 2 + "S.layers=1;"), occ7))
        if occ7[2:] != occ[2:]:
            sys.exit("occupancy bars differ in size: %s vs %s" % (occ, occ7))

        # ---- selected panel ------------------------------------------------------------
        sel = HOME + DEFAULT_BAYS + "S.sel={l:1,d:'N'};"
        f = sh.shot(sel)
        rects[("main", "tSel")] = sh.rect("tSel")
        rects[("main", "bGet")] = sh.rect("bGet", BTN_PAD)
        put(64, "btn_get", crop(f, rects[("main", "bGet")]))
        put(65, "btn_get_down", crop(variant(sel, "bGet", down), rects[("main", "bGet")]))

        # ---- dock panel ------------------------------------------------------------------
        f = sh.shot(dock % ("store", 0, 0))
        for n in ("pTray", "pHand"):
            rects[("main", n)] = sh.rect(n)
        for n in ("bOk", "bCancel"):
            rects[("main", n)] = sh.rect(n, BTN_PAD)
        put(66, "btn_ok", crop(f, rects[("main", "bOk")]))
        put(69, "btn_cancel", crop(f, rects[("main", "bCancel")]))
        put(74, "row_tray_ok", crop(f, rects[("main", "pTray")]))
        put(76, "row_hand_clear", crop(f, rects[("main", "pHand")]))
        put(67, "btn_ok_down", crop(variant(dock % ("store", 0, 0), "bOk", down), rects[("main", "bOk")]))
        put(70, "btn_cancel_down", crop(variant(dock % ("store", 0, 0), "bCancel", down), rects[("main", "bCancel")]))
        f = sh.shot(dock % ("store", 1, 1))
        put(68, "btn_ok_off", crop(f, rects[("main", "bOk")]))
        put(75, "row_tray_wait", crop(f, rects[("main", "pTray")]))
        put(77, "row_hand_block", crop(f, rects[("main", "pHand")]))
        f = sh.shot(dock % ("get", 0, 0))
        rects[("main", "bTaken")] = sh.rect("bTaken", BTN_PAD)
        put(71, "btn_taken", crop(f, rects[("main", "bTaken")]))
        put(72, "btn_taken_down", crop(variant(dock % ("get", 0, 0), "bTaken", down), rects[("main", "bTaken")]))
        put(73, "btn_taken_off", crop(sh.shot(dock % ("get", 1, 0)), rects[("main", "bTaken")]))

        # ---- progress panel ----------------------------------------------------------------
        sh.shot(HOME + "S.job={kind:'store',l:1,d:'NE',steps:['调取空托盘到出入口','-','-','-','-','-'],i:0};S.page='prog';")
        for n in ("tJob", "tStep", "tIdx", "jStep", "nEta"):
            rects[("main", n)] = sh.rect(n)
        bar = rects[("main", "jStep")]
        width = "document.querySelector('[data-ctl=\"jStep\"]').firstChild.style.width='%s';"
        put(89, "bar_empty", crop(variant(prog, "jStep", width.replace('"jStep"', '"%s"') % ("%s", "0")), bar))
        put(90, "bar_full", crop(variant(prog, "jStep", width.replace('"jStep"', '"%s"') % ("%s", "100%%")), bar))

        # ---- fault, e-stop -----------------------------------------------------------------
        put(1, "bg_fault", sh.shot("go('fault');", FAULT_DYN))
        f = sh.shot("go('fault');")
        for n in ("tClk", "tCode", "tTitle", "tDesc", "c0", "c1"):
            rects[("fault", n)] = sh.rect(n)
        rects[("fault", "bHome")] = sh.rect("bHome", BTN_PAD)
        put(78, "chk0_off", crop(f, rects[("fault", "c0")]))
        put(80, "chk1_off", crop(f, rects[("fault", "c1")]))
        put(82, "btn_home_off", crop(f, rects[("fault", "bHome")]))
        f = sh.shot("go('fault');S.chk=[1,1];")
        put(79, "chk0_on", crop(f, rects[("fault", "c0")]))
        put(81, "chk1_on", crop(f, rects[("fault", "c1")]))
        put(83, "btn_home", crop(f, rects[("fault", "bHome")]))
        put(84, "btn_home_down", crop(variant("go('fault');S.chk=[1,1];", "bHome", down), rects[("fault", "bHome")]))
        put(2, "bg_estop", sh.shot("go('estop');"))

        # ---- PIN boxes -----------------------------------------------------------------------
        f = sh.shot("go('pwd');S.pin='1';")
        for i in range(4):
            rects[("pwd", "d%d" % i)] = sh.rect("d%d" % i)
        put(92, "pin_full", crop(f, rects[("pwd", "d0")]))
        put(91, "pin_empty", crop(f, rects[("pwd", "d1")]))

        # ---- self check: rebuild the default home screen from the pictures -------------------
        ref = sh.shot(HOME + DEFAULT_BAYS + "S.lift=1;S.head='S';", ["tClk", "nFree", "tTot"])
        browser.close()

    if sorted(pics) != list(range(93)):
        sys.exit("picture ids are not 0..92: missing %s" % sorted(set(range(93)) - set(pics)))

    comp = pics[0][1].copy()
    comp.paste(pics[3][1], PANEL_RECT[:2])
    default = {"E": 2, "NE": 1, "N": 2, "NW": 1, "W": 1, "SW": 2, "S": 1, "SE": 1}
    for di, d in enumerate(DIRS):
        comp.paste(pics[8 + di * 5 + default[d]][1], BAY_RECT[d][:2])
    comp.paste(pics[48 + DIRS.index("S")][1], HUB_RECT[:2])
    for pid, key in ((57, "tab1"), (60, "tab2"), (86, None), (61, "bStore")):
        if key:
            comp.paste(pics[pid][1], rects[("main", key)][:2])
    # the occupancy bar is partly filled in the reference: blank it in both before comparing
    for im in (comp, ref):
        r = rects[("main", "jOcc")]
        ImageDraw.Draw(im).rectangle((r[0], r[1], r[0] + r[2] - 1, r[1] + r[3] - 1), fill=(0, 0, 0))
    bad_mask = visible_diff(comp, ref)
    bad = count(bad_mask)
    if bad:
        print("rebuild differs inside", bad_mask.getbbox())

    # ---- write files --------------------------------------------------------------------
    os.makedirs(OUT, exist_ok=True)
    for old in os.listdir(OUT):
        if old.endswith(".png"):
            os.remove(os.path.join(OUT, old))
    total = 0
    for pid in range(93):
        name, img = pics[pid]
        img.save(os.path.join(OUT, "%02d_%s.png" % (pid, name)))
        total += img.width * img.height * 2

    # contact sheet
    cols, cell_w, cell_h = 8, 120, 110
    small = [p for p in range(93) if pics[p][1].width < 400]
    sheet = Image.new("RGB", (cols * cell_w, ((len(small) + cols - 1) // cols) * cell_h), (30, 32, 36))
    dr = ImageDraw.Draw(sheet)
    for i, pid in enumerate(small):
        name, img = pics[pid]
        th = img.copy()
        th.thumbnail((cell_w - 8, cell_h - 22))
        x, y = (i % cols) * cell_w + 4, (i // cols) * cell_h + 4
        sheet.paste(th, (x, y))
        dr.text((x, y + cell_h - 20), "%d %s" % (pid, name[:16]), fill=(200, 200, 200))
    sheet.save(os.path.join(DOC, "素材预览.png"))

    # control rectangles
    lines = ["# 控件坐标", "",
             "由 `tools/export_hmi_assets.py` 从原型量出，单位像素，格式 x, y, 宽, 高。不要手改，改原型后重新运行脚本。", "",
             "图片和按钮控件必须按表里的矩形放，尺寸和对应图片一致。"
             "文本和数字控件表里给的是原型里文字的实际范围，控件可以做得更宽，左上角对齐即可。", "",
             "| 页面 | 控件 | x | y | 宽 | 高 |", "|------|------|---|---|----|----|"]
    for di, d in enumerate(DIRS):
        r = BAY_RECT[d]
        lines.append("| main | b%d | %d | %d | %d | %d |" % ((di,) + r))
    lines.append("| main | hub | %d | %d | %d | %d |" % HUB_RECT)
    lines.append("| main | pPanel | %d | %d | %d | %d |" % PANEL_RECT)
    for (pg, n), r in rects.items():
        lines.append("| %s | %s | %d | %d | %d | %d |" % ((pg, n) + r))
    lines += ["", "| 图片编号 | 文件 | 宽 | 高 |", "|----------|------|----|----|"]
    for pid in range(93):
        name, img = pics[pid]
        lines.append("| %d | %02d_%s.png | %d | %d |" % (pid, pid, name, img.width, img.height))
    with io.open(os.path.join(DOC, "控件坐标.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print("93 pictures, %.2f MB on the screen (16-bit)" % (total / 1048576.0))
    print("pixels changing outside the bay rectangles:", leaks)
    print("home screen rebuilt from pictures: %d differing pixels" % bad)


if __name__ == "__main__":
    main()
