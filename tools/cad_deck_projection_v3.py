"""从已有甲板俯视轮廓推导主视与左视的可见/隐藏竖向边。

视为厚度恒定的板件；按第一角投影，从 -Y 看主视图，从 -X 看左视图。
按俯视轮廓射线判断最前方的边；装配孔不在本程序的计算范围内。
"""
import json
from math import atan2, cos, degrees, radians, sin, sqrt
from pathlib import Path
import sys

from check_cad_drawings_v3 import edge, entities, field, near, point

EPS = 1e-5
ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs" / "archive" / "cad" / "图纸_v3_草案"


def on_arc(angle, start, end):
    return (angle - start) % 360 <= (end - start) % 360 + EPS


def get_profile(path):
    items = entities(path)
    hdim = next(e for e in items if e["type"] == "DIMENSION" and near(float(field(e, 50, "0")), 0))
    x0, y0 = point(hdim, 13, 23)
    length = float(field(hdim, 42))
    vdim = next(e for e in items if e["type"] == "DIMENSION" and near(float(field(e, 50, "0")), 90))
    width = float(field(vdim, 42))
    segments = []
    for e in items:
        if e["type"] not in ("LINE", "ARC") or field(e, 8) != "OUTLINE":
            continue
        endpoints = edge(e)
        if not all(x0 - EPS <= x <= x0 + length + EPS and y0 - EPS <= y <= y0 + width + EPS
                   for x, y in endpoints):
            continue
        if e["type"] == "LINE":
            segments.append(("line", tuple((x - x0, y - y0) for x, y in endpoints)))
        else:
            x, y = point(e, 10, 20)
            segments.append(("arc", ((x-x0, y-y0), float(field(e, 40)),
                                      float(field(e, 50)), float(field(e, 51)))))
    return length, width, segments


def arc_points(data):
    (cx, cy), radius, start, end = data
    angles = [start, end] + [a for a in (0, 90, 180, 270) if on_arc(a, start, end)]
    return [(cx + radius*cos(radians(a)), cy + radius*sin(radians(a))) for a in angles]


def intersections(segments, axis, coordinate):
    """交点在视线深度方向的坐标；axis=0 用 x 投影、axis=1 用 y 投影。"""
    found = []
    depth = 1 - axis
    for kind, data in segments:
        if kind == "line":
            p, q = data
            delta = q[axis] - p[axis]
            if abs(delta) < EPS:
                if abs(coordinate - p[axis]) < EPS:
                    found.extend((p[depth], q[depth]))
                continue
            t = (coordinate - p[axis]) / delta
            if -EPS <= t <= 1 + EPS:
                found.append(p[depth] + t * (q[depth] - p[depth]))
        else:
            center, radius, start, end = data
            v = coordinate - center[axis]
            if abs(v) > radius + EPS:
                continue
            step = sqrt(max(0.0, radius * radius - v * v))
            for dep in (center[depth] - step, center[depth] + step):
                xy = (coordinate, dep) if axis == 0 else (dep, coordinate)
                a = degrees(atan2(xy[1] - center[1], xy[0] - center[0])) % 360
                if on_arc(a, start, end):
                    found.append(dep)
    return found


def projection(length, width, segments, axis):
    bound = length if axis == 0 else width
    candidates = []
    for kind, data in segments:
        candidates.extend(data if kind == "line" else arc_points(data))
    grouped = {}
    for p in candidates:
        if p[axis] < EPS or p[axis] > bound-EPS:
            continue
        key = round(p[axis], 5)
        grouped.setdefault(key, []).append(p[1-axis])
    visible, hidden = [], []
    for coord, depths in sorted(grouped.items()):
        hits = intersections(segments, axis, coord)
        if not hits:
            raise ValueError(f"轮廓投影无交点：{coord}")
        frontmost = min(hits)
        (visible if any(abs(v-frontmost) < 0.0001 for v in depths) else hidden).append(coord)
    return visible, hidden


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else SOURCE
    result = {}
    for code in ("P05", "P06"):
        paths = list(src.glob(f"{code}_*.dxf"))
        if len(paths) != 1:
            raise ValueError(f"{code}: 预期一个 DXF，实际 {len(paths)}")
        length, width, segs = get_profile(paths[0])
        front_visible, front_hidden = projection(length, width, segs, 0)
        left_visible, left_hidden = projection(length, width, segs, 1)
        result[code] = {"front_visible": front_visible, "front_hidden": front_hidden,
                        "left_visible": left_visible, "left_hidden": left_hidden}
    print(json.dumps(result, ensure_ascii=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
