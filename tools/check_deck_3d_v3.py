"""比较甲板 DXF 轮廓的解析面积与 AutoCAD 三维实体体积。"""

import math
import sys
from pathlib import Path

from cad_deck_projection_v3 import get_profile


ROOT = Path(__file__).resolve().parents[1]
DRAWINGS = ROOT / "docs" / "archive" / "cad" / "图纸_v3_完善版"


def edge_with_signed_area(segment):
    kind, data = segment
    if kind == "line":
        (x1, y1), (x2, y2) = data
        return (x1, y1), (x2, y2), (x1 * y2 - x2 * y1) / 2
    (cx, cy), radius, start, end = data
    a, b = math.radians(start), math.radians(end)
    while b <= a:
        b += 2 * math.pi
    p = cx + radius * math.cos(a), cy + radius * math.sin(a)
    q = cx + radius * math.cos(b), cy + radius * math.sin(b)
    signed_area = (
        radius * cx * (math.sin(b) - math.sin(a))
        + radius * cy * (math.cos(a) - math.cos(b))
        + radius**2 * (b - a)
    ) / 2
    return p, q, signed_area


def board_area(path):
    _, _, segments = get_profile(path)
    edges = [edge_with_signed_area(segment) for segment in segments]
    adjacency = {}

    def key(point):
        return round(point[0], 4), round(point[1], 4)

    for index, (a, b, _) in enumerate(edges):
        adjacency.setdefault(key(a), []).append((index, True))
        adjacency.setdefault(key(b), []).append((index, False))
    if any(len(items) != 2 for items in adjacency.values()):
        raise ValueError(f"DXF 轮廓未闭合或包含分叉：{path.name}")

    unused = set(range(len(edges)))
    areas = []
    while unused:
        start = key(edges[next(iter(unused))][0])
        current = start
        area = 0.0
        while True:
            choices = [(index, forward) for index, forward in adjacency[current] if index in unused]
            if not choices:
                raise ValueError(f"DXF 轮廓未闭合：{path.name}")
            index, forward = choices[0]
            unused.remove(index)
            a, b, contribution = edges[index]
            area += contribution if forward else -contribution
            current = key(b if forward else a)
            if current == start:
                break
        areas.append(abs(area))
    areas.sort()
    return areas[-1] - sum(areas[:-1])


def main():
    if len(sys.argv) != 3:
        raise SystemExit("用法：py tools/check_deck_3d_v3.py 一层三维体积 二层三维体积")
    for code, actual in zip(("P05", "P06"), map(float, sys.argv[1:])):
        path, = DRAWINGS.glob(code + "*.dxf")
        expected = board_area(path) * 5
        difference = abs(actual - expected)
        # 四个支撑臂口袋与连接段的布尔切口各重叠 0.001 mm，带来 0.24 mm³ 名义差异。
        if difference > 0.3:
            raise AssertionError(f"{code}: 三维体积与二维轮廓不符，差 {difference:.6f} mm³")
        print(f"{code}: 三维体积与 DXF 解析轮廓相差 {difference:.4f} mm³，检查通过")


if __name__ == "__main__":
    main()
