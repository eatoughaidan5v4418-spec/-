"""检查 v4 三视图的轮廓、候选孔和三维板件体积是否一致。"""

import argparse
import csv
import math
from pathlib import Path

from check_cad_drawings_v3 import edge, entities, field, has_edge, near, point
from check_deck_3d_v3 import board_area


ROOT = Path(__file__).resolve().parents[1]


def require_close(actual, expected, tolerance=0.001):
    if abs(actual - expected) > tolerance:
        raise AssertionError(f"实际 {actual:.6f}，期望 {expected:.6f}")


def read_drawing(path, length, width):
    items = entities(path)
    dims = [e for e in items if e["type"] == "DIMENSION" and field(e, 8) == "DIMENSIONS"]
    h = next(e for e in dims if near(float(field(e, 50, "0")), 0) and near(float(field(e, 42)), length))
    v = next(e for e in dims if near(float(field(e, 50, "0")), 90) and near(float(field(e, 42)), width))
    x0, y0 = point(h, 13, 23)
    if any(abs(a - b) > 0.0001 for a, b in zip((x0, y0), point(v, 13, 23))):
        raise AssertionError(f"{path.name}: 尺寸原点不一致")
    circles = []
    for entity in items:
        if entity["type"] != "CIRCLE" or field(entity, 8) != "PROPOSED_HOLES":
            continue
        x, y = point(entity, 10, 20)
        circles.append((x - x0, y - y0, float(field(entity, 40))))
    return x0, y0, circles


def compare_circles(actual, expected, label):
    remaining = actual[:]
    for target in expected:
        found = next((i for i, item in enumerate(remaining)
                      if all(abs(a - b) < 0.0001 for a, b in zip(item, target))), None)
        if found is None:
            raise AssertionError(f"{label}: 缺少孔或沉孔 {target}")
        remaining.pop(found)
    if remaining:
        raise AssertionError(f"{label}: 有意外的候选孔 {remaining}")


def rotation(radius, degrees):
    radians = math.radians(degrees)
    return radius * math.cos(radians), radius * math.sin(radians)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("drawings", nargs="?", type=Path, default=ROOT / "docs" / "cad" / "图纸_v4_干涉调整")
    parser.add_argument("assembly", nargs="?", type=Path, default=ROOT / "docs" / "cad" / "三维装配_v4_干涉调整")
    args = parser.parse_args()
    files = {}
    specs = {"P02R": (520, 520), "P03C": (174, 96), "P05R": (500, 500),
             "P06R": (500, 500), "P07R": (116, 116)}
    for code in specs:
        matches = list(args.drawings.glob(f"{code}_*.dxf"))
        if len(matches) != 1:
            raise AssertionError(f"{code} 应有一个 DXF，实际 {len(matches)}")
        files[code] = matches[0]

    _, _, actual = read_drawing(files["P02R"], *specs["P02R"])
    expected = []
    for angle in (22.5, 202.5):
        a = math.radians(angle)
        for sign in (-1, 1):
            expected.append((260 + 140*math.cos(a) - sign*16*math.sin(a),
                             260 + 140*math.sin(a) + sign*16*math.cos(a), 2.25))
    sx, sy = rotation(140, 112.5)
    expected.append((260 + sx, 260 + sy, 6))
    expected += [(260 + sx + x, 260 + sy + y, 1.7) for x in (-15.5, 15.5) for y in (-15.5, 15.5)]
    expected += [(260 + x + o, 260 + y + o, 2.25)
                 for x in (-205, 205) for y in (-205, 205) for o in (-12, 12)]
    compare_circles(actual, expected, "P02R")
    items = entities(files["P02R"])
    horizontal = next(e for e in items if e["type"] == "DIMENSION" and
                      field(e, 8) == "DIMENSIONS" and near(float(field(e, 50, "0")), 0) and
                      near(float(field(e, 42)), 520))
    x0, y0 = point(horizontal, 13, 23)
    window = [edge(e) for e in items if e["type"] == "LINE" and field(e, 8) == "PROPOSED_HOLES"]
    for a, b in (((235, 235), (285, 235)), ((285, 235), (285, 285)),
                 ((285, 285), (235, 285)), ((235, 285), (235, 235))):
        if not has_edge(window, (a[0]+x0, a[1]+y0), (b[0]+x0, b[1]+y0)):
            raise AssertionError("P02R: 中心 50×50 窗口缺边")

    _, _, actual = read_drawing(files["P03C"], *specs["P03C"])
    cx, cy = 85, 48
    expected = [(cx, cy + y, 1.7) for y in (-8, 8)]
    a = math.radians(20)
    for u in (-29, 29):
        for v in (-29, 29):
            x, y = cx + u*math.cos(a)-v*math.sin(a), cy + u*math.sin(a)+v*math.cos(a)
            expected.extend(((x, y, 2.25), (x, y, 3.2)))
    expected.append((cx - 70.5, cy - 23.5, 3.2))
    expected += [(cx - 70.5 + x, cy - 23.5 + y, 1.4)
                 for x in (-11.5, 11.5) for y in (-11.5, 11.5) if not (x == 11.5 and y == 11.5)]
    expected.append((cx + 83, cy - 23.5, 1.7))
    compare_circles(actual, expected, "P03C")

    _, _, actual = read_drawing(files["P07R"], *specs["P07R"])
    expected = [(58, 58, 12)]
    expected += [(58 + x, 58 + y, 2.25) for x in (-29, 29) for y in (-29, 29)]
    for x in (-15.5, 15.5):
        for y in (-15.5, 15.5):
            expected.extend(((58 + x, 58 + y, 1.7), (58 + x, 58 + y, 3.1)))
    for angle in (22.5, 112.5, 202.5):
        for radius in (44, 52):
            x, y = rotation(radius, angle)
            expected.append((58 + x, 58 + y, 1.7))
    compare_circles(actual, expected, "P07R")

    areas = {code: board_area(files[code]) for code in ("P03C", "P05R", "P06R")}
    require_close(areas["P03C"], 14492, 0.0001)
    require_close(areas["P05R"], 211540.779018174, 0.001)
    require_close(areas["P06R"], 199950.693699592, 0.001)
    with (args.assembly / "模型零件与范围.csv").open(encoding="utf-8-sig", newline="") as stream:
        parts = {row["编号"]: row for row in csv.DictReader(stream)}
    pi = math.pi
    volumes = {
        "BASE": (520*520-50*50-pi*(6**2+4*1.7**2+12*2.25**2))*6,
        "LIFT_DISC": pi*(58**2-12**2)*5-pi*(4*2.25**2*5+4*(1.7**2*5+(3.1**2-1.7**2)*3.2)+6*1.7**2*5),
        "TRANSFER_PLATE": areas["P03C"]*3-pi*(2*1.7**2*3+4*(2.25**2*3+(3.2**2-2.25**2)*1.8)+3.2**2*3+3*1.4**2*3+1.7**2*3),
        "DECK_L1": areas["P05R"]*5,
        "DECK_L2": areas["P06R"]*5,
    }
    for part_id, expected in volumes.items():
        value = parts[part_id].get("体积_mm3", "")
        if not value:
            raise AssertionError(f"{part_id} 缺少三维实体体积，无法核对")
        require_close(float(value), expected, 0.3 if part_id.startswith("DECK_") else 0.01)
    print("P02R、P03C、P07R 的候选孔坐标及半径通过核对。")
    print("P03C、P05R、P06R 的俯视轮廓闭合；已有三维体积与图纸一致。")
    print("候选孔和材料强度仍需实物复核，不代表加工批准。")


if __name__ == "__main__":
    main()
