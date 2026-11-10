"""绘制 v7 活动线束试配示意图；几何为图解，不是 CAD 碰撞校核。"""
from __future__ import annotations

import html
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "cad" / "走线方案_v7"
W, H = 2400, 1720
INK, MUTED = "#17334a", "#5d7283"
BLUE, PURPLE, AMBER, RED = "#087f8c", "#7254ad", "#d99422", "#c75146"
GRID, PANEL, GHOST = "#dce6ec", "#ffffff", "#a8bac5"


class SVG:
    def __init__(self):
        self.items = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
                      '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 Z" fill="#5d7283"/></marker></defs>',
                      f'<rect width="{W}" height="{H}" fill="#eef3f6"/>']

    def add(self, raw): self.items.append(raw)
    def rect(self, x, y, w, h, fill, stroke="none", sw=1, radius=0, extra=""):
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>')
    def line(self, x1, y1, x2, y2, color=INK, width=3, extra=""):
        self.add(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{width}" stroke-linecap="round" {extra}/>')
    def path(self, d, color=INK, width=3, fill="none", extra=""):
        self.add(f'<path d="{d}" fill="{fill}" stroke="{color}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round" {extra}/>')
    def circle(self, x, y, r, fill="none", stroke=INK, sw=2, extra=""):
        self.add(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>')
    def text(self, x, y, value, size=26, color=INK, weight=400, anchor="start", extra=""):
        self.add(f'<text x="{x}" y="{y}" fill="{color}" font-family="Microsoft YaHei, Noto Sans CJK SC, sans-serif" font-size="{size}" font-weight="{weight}" text-anchor="{anchor}" {extra}>{html.escape(str(value))}</text>')
    def lines(self, x, y, values, size=26, gap=39, color=INK, weight=400):
        for i, value in enumerate(values): self.text(x, y+i*gap, value, size, color, weight)
    def badge(self, x, y, value, fill=BLUE):
        self.circle(x, y, 27, fill, "none")
        self.text(x, y+9, value, 25, "white", 700, "middle")
    def save(self, name):
        (OUT / name).write_text("\n".join(self.items + ["</svg>"]), encoding="utf-8")


def header(s, title, subtitle):
    s.text(70, 82, title, 52, INK, 700)
    s.text(72, 135, subtitle, 26, MUTED)
    s.rect(2040, 43, 280, 53, "#fff3d7", radius=24)
    s.text(2180, 79, "试配方案 · 未校核", 23, "#8a5b12", 700, "middle")


def panel_heading(s, x, y, number, title, subtitle):
    s.badge(x+28, y-9, number)
    s.text(x+75, y, title, 34, INK, 700)
    s.text(x+75, y+43, subtitle, 22, MUTED)


def label_box(s, x, y, heading, rows, color=BLUE):
    s.circle(x, y-9, 8, color, "none")
    s.text(x+22, y, heading, 29, INK, 700)
    s.lines(x+22, y+40, rows, 23, 35, MUTED)


def diagram_lift():
    s = SVG()
    header(s, "v7 活动线束：升降拖链", "67.5° 方位的侧视剖面 · 低位和高位叠加 · 图中机构及线束未按共同尺度绘制")
    s.rect(55, 175, 1400, 1360, PANEL, radius=22)
    s.rect(1480, 175, 865, 1360, PANEL, radius=22)
    panel_heading(s, 90, 245, "1", "先从底座走到升降平台", "底座固定端 → 拖链 → 移动端 → 平台分线点")
    # 径向剖切：外侧向右；Z 坐标只用于解释线束相对关系。
    x0, sx, bottom, sz = 405.0, 3.25, 1260.0, 2.75
    xr = lambda r: x0 + r*sx
    yz = lambda z: bottom - z*sz
    # 原占位与示例拖链的冲突。
    s.rect(xr(130), yz(250), 22*sx, (250-40)*sz, "#e6f2f3", BLUE, 2, 0, 'stroke-dasharray="9 8" opacity="0.7"')
    s.text(xr(130)-70, yz(250)-18, "v7 拖链占位", 21, BLUE, 600)
    s.line(112, yz(0), 1345, yz(0), "#6f8491", 12)
    s.text(118, yz(0)+36, "底板 Z=0", 22, MUTED)
    for z, name in [(100, "一层甲板 Z=100"), (190, "二层甲板 Z=190")]:
        y=yz(z)
        # 示意 67.5° 扩口：原口袋 r125..160，新增缺口 r160..约170。
        s.line(xr(170), y, 1270, y, "#8ca1af", 13)
        s.line(xr(160), y, xr(170), y, AMBER, 13, 'stroke-dasharray="8 7"')
        s.text(1050, y-19, name, 23, MUTED, 600)
    # 中心机构。低位和高位只是参考姿态。
    s.line(x0, yz(10), x0, yz(260), "#c6d4dc", 2, 'stroke-dasharray="9 9"')
    s.rect(xr(-21), yz(58), 42*sx, 40*sz, "#9aadb9", radius=8)
    s.text(x0, yz(40)+10, "θ 电机", 23, "#ffffff", 700, "middle")
    s.text(x0, yz(30)+10, "只升降", 19, "#ffffff", 400, "middle")
    s.rect(xr(-58), yz(78), 116*sx, 5*sz, "#96adba", radius=4)
    s.rect(xr(-38), yz(86), 76*sx, 8*sz, "#c2cdd4", radius=3)
    s.rect(xr(-90), yz(89), 183*sx, 3*sz, "#648da1", radius=3)
    s.rect(xr(-38), yz(103), 125*sx, 3*sz, "#d4dfe4", radius=3)
    s.rect(xr(-70), yz(131), 25*sx, 25*sz, "#b1c5cf", "#698796", 2, 5)
    s.text(xr(-70)-25, yz(131)-14, "拨叉 U 电机", 22, INK, 700)
    s.text(155, yz(89)-30, "P03E 转运板", 22, INK, 700)
    # 受约束线环试配区，落在 P03E 下方、轴承外侧。
    s.rect(xr(60), yz(86), 30*sx, 8*sz, "#f8dfad", AMBER, 2, 4, 'stroke-dasharray="6 4"')
    s.text(xr(90)+14, yz(86)-10, "线环试配区 → 见图 2", 21, "#92621e", 700)
    # 新增移动端支架，与升降中心盘固定；原模型无此臂。
    yj=yz(73)
    s.line(xr(58), yj, xr(116), yj, AMBER, 15, 'stroke-dasharray="14 8"')
    s.text(xr(60), yj+42, "新增随升降支架", 22, "#98600d", 700)
    s.text(xr(60), yj+69, "穿过 67.5° 甲板槽", 19, MUTED)
    # 拖链理想中心线：示例 r=116/166，R25；链本体尚无规格。
    xM, xF = xr(116), xr(166)
    arcR_x, arcR_y = 25*sx, 25*sz
    def chain_path(zlift):
        zM=zlift-27
        zC=(157 + 40 + zM)/2
        return (f'M {xF:.1f} {yz(40):.1f} L {xF:.1f} {yz(zC):.1f} '
                f'A {arcR_x:.1f} {arcR_y:.1f} 0 0 0 {xM:.1f} {yz(zC):.1f} L {xM:.1f} {yz(zM):.1f}')
    s.path(chain_path(190), GHOST, 8, extra='stroke-dasharray="13 10" opacity="0.85"')
    s.path(chain_path(100), "#d7e7e9", 24)
    s.path(chain_path(100), BLUE, 6)
    s.path(chain_path(100), PURPLE, 3, extra='stroke-dasharray="12 10"')
    s.text(1045, yz(180)-15, "高位形态", 22, MUTED, 600)
    s.text(1045, yz(135)+10, "低位形态", 22, BLUE, 600)
    # 拖链移动端到分线点、固定端到底座电控。
    s.line(xr(58), yj-10, xM, yj-10, BLUE, 6)
    s.line(xr(58), yj-2, xM, yj-2, PURPLE, 4, 'stroke-dasharray="10 7"')
    s.path(f'M {xF} {yz(40)} L {xF} {yz(8)} L 308 {yz(8)}', BLUE, 6)
    s.path(f'M {xF-9} {yz(40)} L {xF-9} {yz(11)} L 308 {yz(11)}', PURPLE, 4, extra='stroke-dasharray="10 7"')
    s.rect(105, 1116, 203, 97, "#eaf1f5", "#a6bac5", 2, 9)
    s.text(206, 1153, "底座电控区", 24, INK, 700, "middle")
    s.text(206, 1187, "主控 + 驱动", 20, MUTED, 400, "middle")
    # 分线点至旋转电机与原点霍尔的终端，走向为功能示意。
    s.path(f'M {xr(58):.1f} {yj-10:.1f} L {xr(47):.1f} {yj-10:.1f} L {xr(47):.1f} {yz(53):.1f} L {xr(21):.1f} {yz(53):.1f}', BLUE, 6)
    s.path(f'M {xr(58):.1f} {yj-2:.1f} L {xr(67):.1f} {yj-2:.1f} L {xr(67):.1f} {yz(55):.1f}', PURPLE, 4, extra='stroke-dasharray="10 7"')
    s.text(615, 1160, "θ 霍尔线", 20, PURPLE, 700)
    s.text(615, 1188, "传感器座待定", 18, MUTED)
    for x,y,name in [(xF,yz(40),"J0"),(xM,yj,"J1"),(xr(58),yj,"J2")]:
        s.circle(x,y,11,"#fff",BLUE,4)
        s.text(x+14,y-16,name,23,BLUE,700)
    s.text(1050, yz(40)+10, "J0 底座固定端", 22, INK, 600)
    s.text(795, yj+82, "J1 移动端", 22, INK, 600)
    s.text(280, 1420, "低位 Z=100：线环顶部 Z≈160；高位 Z=190：顶部 Z≈205。", 23, MUTED)
    s.text(280, 1456, "这是 R25 中心线示例；实际链体、端头和公差尚未计入。", 23, MUTED)
    # 右侧说明
    panel_heading(s, 1515, 245, "2", "如何固定、哪里要改", "带编号的点均是本方案新增的位置")
    label_box(s, 1545, 350, "J0  底座固定端", ["设在 67.5° 扇区，示例 r≈166、Z≈40。", "增加底座立架和线夹；线先固定再进拖链。"])
    label_box(s, 1545, 495, "J1  拖链移动端", ["示例 r≈116，随升降运动。", "新增支架连接升降盘；插头不承受拉力。"], AMBER)
    label_box(s, 1545, 640, "J2  平台分线点", ["固定在只升降、不旋转的一侧。", "θ 电机与原点霍尔在此分出。"])
    label_box(s, 1545, 785, "P05R / P06R  两层甲板", ["原口袋外端 r=160；本示例外支路约 r=166。", "需要按实物扩大通道，并复核车位支承。"], AMBER)
    label_box(s, 1545, 930, "链体、线径与弯曲", ["示例 R25：中心线理想长度约 236 mm。", "它不是成品规格或采购长度；两侧需分隔。"], AMBER)
    s.rect(1530, 1060, 765, 200, "#fff7e7", "#efd59e", 2, 14)
    s.lines(1560, 1105, ["为什么原占位不够？", "若弯曲面沿径向，两个直段中心距为 2R。", "v7 占位径向仅 22 mm：R25 示例需 50 mm，", "还未计链体厚度、端头和活动余量。"], 23, 38, "#76541d")
    s.text(1545, 1335, "预留区是模型占位，不是真实拖链。", 25, RED, 700)
    s.text(1545, 1375, "尺寸冻结前，需补做运动和碰撞检查。", 23, MUTED)
    # 底部线束流向条
    s.rect(55, 1565, 2290, 110, "#dfebf0", radius=14)
    s.text(85, 1610, "拖链内", 28, INK, 700)
    s.text(215, 1610, "θ 电机 4 芯", 25, BLUE, 700)
    s.text(480, 1610, "U 电机 4 芯", 25, BLUE, 700)
    s.text(742, 1610, "θ 霍尔 3 芯", 25, PURPLE, 700)
    s.text(1010, 1610, "转台检测 5 芯 + 1 备用", 25, PURPLE, 700)
    s.text(85, 1650, "电机线与检测线分束；具体线径、分隔、接头与弯曲半径按实物确认。", 22, MUTED)
    s.save("01_升降拖链走线.svg")


def polygon(points): return " ".join(f"{x:.1f},{y:.1f}" for x,y in points)


def diagram_rotary():
    s = SVG()
    header(s, "v7 活动线束：转盘旋转连接", "θ=0 俯视叠加图 · 转运板上方元件与板下候选线环同时显示，颜色用于区分高度")
    s.rect(55, 175, 1400, 1360, PANEL, radius=22)
    s.rect(1480, 175, 865, 1360, PANEL, radius=22)
    panel_heading(s, 90, 245, "1", "从升降侧接到旋转侧", "沿 67.5° 支架来线；一条示意线代表两组线束")
    cx, cy, sc = 700, 845, 4.5
    pt = lambda u,w:(cx+u*sc, cy-w*sc)
    # deck and aperture; pocket is the exact v7 67.5-degree profile.
    s.add('<defs><clipPath id="planclip"><rect x="85" y="335" width="1325" height="1050"/></clipPath></defs><g clip-path="url(#planclip)">')
    s.circle(cx, cy, 102*sc, "#f9fbfc", "#90a8b7", 4)
    a=math.radians(67.5)
    def polar_local(r,w): return pt(r*math.cos(a)-w*math.sin(a),r*math.sin(a)+w*math.cos(a))
    c0=math.sqrt(102*102-7*7)
    pocket=[(c0,-7),(125,-7),(125,-13),(160,-13),(160,13),(125,13),(125,7),(c0,7)]
    s.add(f'<polygon points="{polygon([polar_local(r,w) for r,w in pocket])}" fill="#f9fbfc" stroke="#90a8b7" stroke-width="4"/>')
    s.circle(cx, cy, 90*sc, "#fff4dd", AMBER, 3, 'stroke-dasharray="12 9" opacity="0.65"')
    s.circle(cx, cy, 60*sc, "#f9fbfc", AMBER, 3, 'stroke-dasharray="12 9" opacity="0.90"')
    # Lift disk, bearing square and P03E silhouettes; under-plate zone remains visible.
    s.circle(cx, cy, 58*sc, "#d9e6ec", "#8aa2af", 2, 'opacity="0.55"')
    # P03E schematic outline - centre 96 square, ends 66 wide; ears omitted in this view.
    outline=[(-90,-39),(-50,-39),(-48,-48),(48,-48),(53,-33),(85,-33),(85,-29),(93,-29),(93,-18),(85,-18),(85,33),(53,33),(48,48),(-48,48),(-53,33),(-90,33)]
    s.add(f'<polygon points="{polygon([pt(u,w) for u,w in outline])}" fill="#c5dbe5" fill-opacity="0.48" stroke="#537d90" stroke-width="4"/>')
    s.rect(cx-35.5*sc,cy-35.5*sc,71*sc,71*sc,"none","#6a8190",3,0,f'transform="rotate(-20 {cx} {cy})" stroke-dasharray="8 6"')
    # Linear rail, support strips and belt.
    s.rect(*pt(-85,3.5),170*sc,7*sc,"#7195a5",radius=4)
    for w in (-26.5,28.5):
        x,y=pt(-60,w+2.5); s.rect(x,y,145*sc,5*sc,"#9db7c3",radius=4)
    x1,y1=pt(-74,-23.5); x2,y2=pt(87.5,-23.5)
    s.line(x1,y1,x2,y2,"#657d89",8)
    s.circle(x2,y2,6.5*sc,"#d1dce1","#657d89",3)
    x,y=pt(-88.1,-9.4); s.rect(x,y,28.2*sc,28.2*sc,"#98adba","#5d7787",3,8)
    s.text(x+7,y+67,"U",35,"white",700)
    for u in (-78.5,78.5):
        x,y=pt(u-6.4,17.3); s.rect(x,y,12.8*sc,5.8*sc,"#79a2af",radius=4)
    # Conceptual spiral cable path, below P03E: 1.86 turns to the candidate outlet.
    points=[]
    angle0=math.radians(67.5); endangle=math.atan2(18,58)+4*math.pi
    for i in range(281):
        f=i/280; angle=angle0+(endangle-angle0)*f; radius=82+(math.hypot(58,18)-82)*f
        points.append(pt(radius*math.cos(angle),radius*math.sin(angle)))
    s.add(f'<polyline points="{polygon(points)}" fill="none" stroke="white" stroke-width="17" stroke-linejoin="round" stroke-linecap="round" opacity=".92"/>')
    s.add(f'<polyline points="{polygon(points)}" fill="none" stroke="{PURPLE}" stroke-width="8" stroke-linejoin="round" stroke-linecap="round" stroke-dasharray="14 9"/>')
    # Entry from drag chain and fixed clamp; rotating clamp at P03E.
    p_in=polar_local(116,0); p_anchor=polar_local(88,0); p_spiral=points[0]; p_rot=pt(58,18)
    s.path(f'M {p_in[0]} {p_in[1]} L {p_anchor[0]} {p_anchor[1]} L {p_spiral[0]} {p_spiral[1]}',BLUE,8)
    s.path(f'M {p_in[0]+8} {p_in[1]+5} L {p_anchor[0]+8} {p_anchor[1]+5}',PURPLE,4,extra='stroke-dasharray="10 8"')
    for (x,y),name,clr in [(p_anchor,"JF",BLUE),(p_rot,"JR",PURPLE)]:
        s.circle(x,y,15,"white",clr,5); s.text(x+20,y-16,name,25,clr,700)
    s.add('</g>')
    s.text(120, 455, "井口 R102", 24, MUTED, 700)
    s.text(120, 495, "浅蓝：转运板 P03E", 22, MUTED)
    s.text(120, 530, "灰色虚线：转盘轴承", 22, MUTED)
    s.text(120, 565, "淡黄环：线环候选区", 22, "#9a6c1b")
    s.text(115, 1270, "U 电机", 23, INK, 700)
    s.line(218,1257,x1-30,y1-5,MUTED,2,'marker-end="url(#arrow)"')
    s.text(820, 1270, "拨叉收回 / 伸出微动", 23, INK, 700)
    s.text(562, 1395, "前侧 / DOCK（−Y）", 25, MUTED, 700)
    s.line(700,1350,700,1368,MUTED,3,'marker-end="url(#arrow)"')
    # Right: clear instructions and constraints.
    panel_heading(s, 1515, 245, "2", "先试配的旋转线环", "图中螺旋线只示意功能，实际走向尚未验证")
    label_box(s, 1545, 350, "JF  不旋转侧固定点", ["在 R≈88、67.5° 附近，连接新增支架。", "U 电机线和转台检测线在这里固定。"])
    label_box(s, 1545, 495, "JR  随转盘侧固定点", ["参考局部坐标 u≈+58、w≈+18。", "上方有托盘；出线口及护边位置待复核。"], PURPLE)
    label_box(s, 1545, 640, "环形导槽 / 盖板", ["优先研究 R≈60～90 的轴承外围区域。", "局部超出转运板投影，需独立支承和防护。"], AMBER)
    label_box(s, 1545, 785, "旋转设定", ["保持 −135°～+180° 往返，不连续转圈。", "在中间角 +22.5° 调整初始预留，再测两端。"], PURPLE)
    s.rect(1530, 895, 765, 245, "#fff7e7", "#efd59e", 2, 14)
    s.lines(1558, 936, ["现有高度很紧：", "一层对接时，升降盘顶 Z=78，P03E 底 Z=86。", "两者标高差仅 8 mm，不能当成已测净空。", "线径、护罩、螺钉与运动包络必须一起试配。", "中心轴、法兰和轴承位置不能直接穿线。"], 22, 39, "#76541d")
    label_box(s, 1545, 1235, "旋转侧出线", ["分别去 U 电机、拨叉两端开关、托盘霍尔。", "沿板下固定，过板后避开皮带、滑块和托盘。"], PURPLE)
    s.text(1545, 1410, "若 8 mm 内无法实现，应调整轴系叠层或改用合适旋转接头。", 21, RED, 700)
    s.text(1545, 1445, "任何高度改动都要重核托盘对接及 8 mm 啮合。", 21, MUTED)
    s.rect(55, 1565, 2290, 110, "#dfebf0", radius=14)
    s.text(85, 1610, "去向", 28, INK, 700)
    s.text(205, 1610, "θ 电机 / θ 霍尔：到升降平台为止", 25, BLUE, 700)
    s.text(1065, 1610, "U 电机 / 限位 / 托盘霍尔：经过旋转线环", 25, PURPLE, 700)
    s.text(85, 1650, "JF、JR 位置、线环的弯曲、层间隔离和穿板孔均为试配方案；不得直接按图加工。", 22, MUTED)
    s.save("02_旋转连接走线.svg")


def diagram_connections():
    s = SVG()
    header(s, "v7 活动线束：从哪里接到哪里", "按四组线束看起点、经过的固定点和终点 · 此图是连接关系，不是模块针序图")
    s.rect(55, 175, 2290, 1250, PANEL, radius=22)
    headers=[("底座起点",250),("J0 → J1 拖链",680),("J2 升降平台",1095),("JF → JR 旋转连接",1540),("最终终点",2060)]
    for label,x in headers: s.text(x, 256, label, 29, INK, 700, "middle")
    # Rows share the same mechanical junctions, shown separately for readability.
    rows=[
        ("MT", "θ 轴驱动", "4 芯电机线", "J2 分出", "", "θ 电机两相", BLUE),
        ("ST", "主控 + 3.3 V", "3 芯传感器线", "J2 分出", "", "θ 原点霍尔", PURPLE),
        ("MU", "U 轴驱动", "4 芯电机线", "经过 J2", "经过 JF / JR", "U 电机两相", BLUE),
        ("SU", "主控 + 3.3 V", "5 芯 + 1 备用", "经过 J2", "经过 JF / JR", "U 两限位 + 托盘霍尔", PURPLE),
    ]
    def box(x,y,w,text,fill,stroke):
        s.rect(x,y,w,100,fill,stroke,3,12)
        s.text(x+w/2,y+60,text,25,INK,700,"middle")
    for i,(tag,source,cable,j2,rot,dest,color) in enumerate(rows):
        y=325+i*220
        s.rect(90,y-5,2150,135,"#f7fafb",radius=14)
        s.badge(105,y+62,tag,color)
        box(145,y+8,250,source,"#f0f5f7","#bccbd3")
        box(520,y+8,310,cable,"#eef7f8" if color==BLUE else "#f5f1fa",color)
        box(930,y+8,260,j2,"#f0f5f7","#bccbd3")
        for x1,x2 in ((400,510),(835,920)):
            s.line(x1,y+58,x2,y+58,color,5,'marker-end="url(#arrow)"')
        if rot:
            box(1280,y+8,310,rot,"#fff7e7",AMBER)
            box(1850,y+8,365,dest,"#eef7f8" if color==BLUE else "#f5f1fa",color)
            s.line(1195,y+58,1270,y+58,color,5,'marker-end="url(#arrow)"')
            s.line(1595,y+58,1840,y+58,color,5,'marker-end="url(#arrow)"')
        else:
            box(1365,y+8,375,dest,"#eef7f8" if color==BLUE else "#f5f1fa",color)
            s.line(1195,y+58,1355,y+58,color,5,'marker-end="url(#arrow)"')
            s.text(1970,y+67,"不经过旋转线环",23,MUTED,600,"middle")
    s.rect(95, 1250, 2140, 110, "#fff7e7", "#efd59e", 2, 14)
    s.text(125, 1293, "SU 线束预算", 26, INK, 700)
    s.text(315, 1293, "3.3 V / GND / U 收回 / U 伸出 / 托盘霍尔输出 / 1 芯备用", 25, INK)
    s.text(125, 1333, "前提：微动为无源触点并共地；传感器若需其他电源或隔离，应增加线芯。", 22, MUTED)
    s.rect(55, 1460, 2290, 205, "#dfebf0", radius=14)
    s.text(85, 1510, "安装与接线时", 28, INK, 700)
    s.lines(85, 1555, ["两组电机各自按 A 相、B 相配对；具体颜色与插头针序按电机实物核实。", "J0 / J1 / JF / JR 是固定点；保护拖链与线环中的电缆，不能让插头受力。", "旋转侧短线的穿板口、线夹与避让路径仍需在 v7 三维装配中落实。"], 23, 36, MUTED)
    s.save("03_线束终点和芯数.svg")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    diagram_lift()
    diagram_rotary()
    diagram_connections()
    print(f"已生成三张 SVG 走线示意图：{OUT}")


if __name__ == "__main__":
    main()
