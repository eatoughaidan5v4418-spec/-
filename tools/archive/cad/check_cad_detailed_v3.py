"""核对完善版 DXF 的主轮廓、投影视图、候选孔、备选转运板和平面间隙。

不代替实物测量、三维干涉检查或加工工艺确认。
用法：py tools/archive/cad/check_cad_detailed_v3.py [图纸目录]
"""
from collections import Counter
from math import cos, hypot, radians, sin
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from check_cad_drawings_v3 import check_closed, edge, entities, field, near, near_point, point

ROOT = Path(__file__).resolve().parents[3]
DEFAULT = ROOT / "docs" / "archive" / "cad" / "图纸_v3_完善版"
PARTS = {
    "P01": (125, 60, 3), "P02": (520, 520, 6), "P03": (170, 66, 3),
    "P03B": (170, 96, 3), "P04": (500, 500, 5),
    "P05": (500, 500, 5), "P06": (500, 500, 5),
}
EPS = 1e-4


def find_part(directory, code):
    files = list(directory.glob(f"{code}_*.dxf"))
    assert len(files) == 1, f"{code}: 需要且只能有一个 DXF，实际 {len(files)}"
    return files[0]


def close_set(actual, expected):
    assert len(actual) == len(expected), (actual, expected)
    remaining = list(actual)
    for value in expected:
        hit = next((i for i, p in enumerate(remaining) if near_point(p, value)), None)
        assert hit is not None, (value, remaining)
        remaining.pop(hit)


def hole_centers(items, x, y):
    holes = [e for e in items if e["type"] == "CIRCLE" and field(e, 8) == "PROPOSED_HOLES"]
    return [(point(e, 10, 20)[0]-x, point(e, 10, 20)[1]-y, float(field(e, 40))) for e in holes]


def check_drawing(directory, code, length, width, thickness):
    items = entities(find_part(directory, code))
    dims = [e for e in items if e["type"] == "DIMENSION" and field(e, 8) == "DIMENSIONS"]
    hdim = next(e for e in dims if near(float(field(e, 50, "0")), 0)
                and near(float(field(e, 42)), length))
    x, y = point(hdim, 13, 23)
    vdim = next(e for e in dims if near(float(field(e, 50, "0")), 90)
                and near(float(field(e, 42)), width) and near_point(point(e, 13, 23), (x, y)))
    assert near_point(point(hdim, 14, 24), (x + length, y))
    assert near_point(point(vdim, 14, 24), (x, y + width))

    outline = [e for e in items if e["type"] in ("LINE", "ARC") and field(e, 8) == "OUTLINE"]
    top = [edge(e) for e in outline if all(x-EPS <= px <= x+length+EPS and
                                           y-EPS <= py <= y+width+EPS for px, py in edge(e))]
    check_closed(top, 2 if code == "P05" else 1, code)
    front = [edge(e) for e in outline if e["type"] == "LINE" and all(p[1] > y+width for p in edge(e))]
    assert any(near(a[0], x) and near(b[0], x) and near(abs(a[1]-b[1]), thickness)
               for a, b in front), f"{code}: 主视图厚度不符"
    holes = hole_centers(items, x+length/2, y+width/2)

    if code in ("P02", "P04"):
        expected = []
        for deg in (22.5, 202.5):
            a = radians(deg)
            for sign in (1, -1):
                expected.append((140*cos(a)-sign*16*sin(a), 140*sin(a)+sign*16*cos(a)))
        if code == "P04":
            a = radians(112.5)
            expected.extend((140*cos(a)-sign*18*sin(a), 140*sin(a)+sign*18*cos(a)) for sign in (1, -1))
        assert all(near(r, 2.25) for _, _, r in holes)
        close_set([(hx, hy) for hx, hy, _ in holes], expected)

    if code in ("P03", "P03B"):
        expected = [(0, -8), (0, 8)]
        a = radians(20 if code == "P03B" else 0)
        expected.extend((u*cos(a)-v*sin(a), u*sin(a)+v*cos(a))
                        for u in (-29, 29) for v in (-29, 29))
        close_set([(hx, hy) for hx, hy, _ in holes], expected)
        assert sorted(round(r, 2) for _, _, r in holes) == [1.7, 1.7, 2.25, 2.25, 2.25, 2.25]

    if code in ("P05", "P06"):
        hidden = [edge(e) for e in items if e["type"] == "LINE" and field(e, 8) == "HIDDEN"]
        assert len(hidden) >= 60, f"{code}: 未补足井孔投影隐藏线"
        measurements = [float(field(e, 42)) for e in dims]
        assert all(any(near(value, d) for d in measurements) for value in (14, 26, 35))
        # 前视图中，北侧槽的两条边在一层被挡住，在二层的前向竖井里可见。
        for xx in (x + 243, x + 257):
            from_hidden = any(near(a[0], xx) and near(b[0], xx) and a[1] > y+width for a, b in hidden)
            from_visible = any(near(a[0], xx) and near(b[0], xx) for a, b in front)
            assert (from_hidden, from_visible) == ((True, False) if code == "P05" else (False, True)), code
    print(f"{code}: 轮廓及标注 {length}×{width}×{thickness} mm；候选孔 {len(holes)}")


def check_tray_blank(directory):
    path = next((directory / "托盘空白板轮廓").glob("*.dxf"))
    all_items = entities(path)
    assert len(all_items) == 1 and all_items[0]["type"] == "LWPOLYLINE"
    poly = all_items[0]
    assert int(field(poly, 70)) & 1
    xs, ys = poly["groups"]["10"], poly["groups"]["20"]
    points = [(float(x), float(y)) for x, y in zip(xs, ys)]
    assert points == [(0,10), (10,0), (125,0), (125,60), (10,60), (0,50)]
    print("P01 无孔空白：1 条闭合多段线，125×60、2×C10。")


def check_alternative(directory):
    items = entities(find_part(directory, "P03B"))
    dims = [e for e in items if e["type"] == "DIMENSION"]
    hdim = next(e for e in dims if near(float(field(e, 50, "0")), 0) and near(float(field(e, 42)), 170))
    x, y = point(hdim, 13, 23)
    center = (x+85, y+48)
    edges = [edge(e) for e in items if e["type"] == "LINE" and field(e, 8) == "OUTLINE"]
    top = [p for ends in edges for p in ends if x-EPS <= p[0] <= x+170+EPS and y-EPS <= p[1] <= y+96+EPS]
    envelope = max(hypot(px-center[0], py-center[1]) for px, py in top)
    assert near(envelope, hypot(85, 33)) and 96-envelope >= 4

    # 按购买图片中的 71 方形、58 方孔组；支撑条按旧示意宽 6、中心 ±27。
    theta = radians(20)
    bearing_half = 71*(cos(theta)+sin(theta))/2
    assert bearing_half <= 48
    centers = [(u*cos(theta)-v*sin(theta), u*sin(theta)+v*cos(theta))
               for u in (-29, 29) for v in (-29, 29)]
    head_radius = 4.5  # 9 mm 螺钉头/垫圈，仅用于该平面假设。
    gaps = [24-abs(v)-head_radius if abs(v)<24 else abs(v)-30-head_radius for _, v in centers]
    assert min(gaps) > 2.0, gaps
    assert all(-40 <= u <= 85 for u, _ in centers)
    print(f"P03B 平面假设：旋转半径 {envelope:.2f}，井口余量 {96-envelope:.2f} mm；"
          f"转盘外缘余量 {48-bearing_half:.2f} mm，螺钉头至支撑条最小 {min(gaps):.2f} mm。")
    print("上述数值只覆盖标称二维轮廓与假设的 9 mm 螺钉头；装拆、叠层和偏差未验证。")


def main():
    directory = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    for code, dims in PARTS.items():
        check_drawing(directory, code, *dims)
    check_tray_blank(directory)
    check_alternative(directory)


if __name__ == "__main__":
    main()
