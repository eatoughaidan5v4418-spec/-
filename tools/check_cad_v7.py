"""检查 v7 方案三视图的轮廓、候选孔和三维板件体积。"""

import argparse
import csv
import math
from pathlib import Path

from check_cad_drawings_v3 import entities, field, near, point
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
    parser.add_argument("drawings", nargs="?", type=Path, default=ROOT / "docs" / "cad" / "图纸_v7_加厚夹带")
    parser.add_argument("assembly", nargs="?", type=Path, default=ROOT / "docs" / "cad" / "三维装配_v7_加厚夹带")
    args = parser.parse_args()
    files = {}
    specs = {"P01N": (125, 60), "P02S": (520, 520), "P03E": (183, 96), "P04": (500, 500), "P05R": (500, 500),
             "P06R": (500, 500), "P07R": (116, 116)}
    for code in specs:
        matches = list(args.drawings.glob(f"{code}_*.dxf"))
        if len(matches) != 1:
            raise AssertionError(f"{code} 应有一个 DXF，实际 {len(matches)}")
        files[code] = matches[0]

    x0, y0, _ = read_drawing(files["P01N"], *specs["P01N"])
    tray_entities = entities(files["P01N"])
    pin = [e for e in tray_entities if e["type"] == "CIRCLE" and field(e, 8) == "REFERENCE"]
    if len(pin) != 1 or any(abs(a-b) > 0.0001 for a,b in zip(point(pin[0],10,20), (x0+7,y0+30))) or abs(float(field(pin[0],40))-2)>0.0001:
        raise AssertionError("P01N 定位销应位于距内端 7 mm、居中，直径 4 mm")

    _, _, actual = read_drawing(files["P02S"], *specs["P02S"])
    expected = []
    for angle in (22.5, 202.5):
        a = math.radians(angle)
        for sign in (-1, 1):
            expected.append((260 + 140*math.cos(a) - sign*16*math.sin(a),
                             260 + 140*math.sin(a) + sign*16*math.cos(a), 2.25))
    sx, sy = rotation(140, 112.5)
    for x in (-30, 30):
        for y in (-15.5, 15.5):
            expected.extend(((260+sx+x, 260+sy+y, 2.25), (260+sx+x, 260+sy+y, 4.2)))
    compare_circles(actual, expected, "P02S")
    if any(e["type"] == "LINE" and field(e, 8) == "PROPOSED_HOLES" for e in entities(files["P02S"])):
        raise AssertionError("P02S 出现非预期的中心开窗轮廓")

    _, _, actual = read_drawing(files["P03E"], *specs["P03E"])
    cx, cy = 90, 48
    expected = [(cx, cy + y, r) for y in (-8, 8) for r in (1.7, 2.7)]
    a = math.radians(20)
    for u in (-29, 29):
        for v in (-29, 29):
            x, y = cx + u*math.cos(a)-v*math.sin(a), cy + u*math.sin(a)+v*math.cos(a)
            expected.extend(((x, y, 2.25), (x, y, 3.2)))
    expected.append((cx - 74, cy - 23.5, 3.2))
    expected += [(cx - 74 + x, cy - 23.5 + y, 1.4)
                 for x in (-11.5, 11.5) for y in (-11.5, 11.5) if not (x == 11.5 and y == 11.5)]
    expected.append((cx + 87.5, cy - 23.5, 1.7))
    expected += [(cx + u, cy + w, 1.4) for u in (-56, 56) for w in (-26.5, 28.5)]
    expected += [(cx + u, cy + 22, 1.2) for u in (-81.85, -75.35, 75.35, 81.85)]
    compare_circles(actual, expected, "P03E")

    _, _, actual = read_drawing(files["P04"], *specs["P04"])
    expected = []
    for angle, radius in ((22.5, 16), (202.5, 16), (112.5, 18)):
        cx, cy = rotation(140, angle)
        for sign in (-1, 1):
            dx, dy = rotation(sign*radius, angle+90)
            expected.append((250+cx+dx, 250+cy+dy, 2.25))
    compare_circles(actual, expected, "P04")

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

    areas = {code: board_area(files[code]) for code in ("P01N", "P03E", "P05R", "P06R")}
    require_close(areas["P01N"], 7400, 0.0001)
    require_close(areas["P03E"], 14896, 0.0001)
    require_close(areas["P05R"], 208817.409533072, 0.001)
    require_close(areas["P06R"], 197611.279099042, 0.001)
    with (args.assembly / "模型零件与范围.csv").open(encoding="utf-8-sig", newline="") as stream:
        parts = {row["编号"]: row for row in csv.DictReader(stream)}
    pi = math.pi
    volumes = {
        "CENTER_TRAY": areas["P01N"]*3,
        "BASE": 520*520*6-pi*(8*2.25**2*6+4*(4.2**2-2.25**2)*2.5),
        "LIFT_DISC": pi*(58**2-12**2)*5-pi*(4*2.25**2*5+4*(1.7**2*5+(3.1**2-1.7**2)*3.2)+6*1.7**2*5),
        "TRANSFER_PLATE": areas["P03E"]*3-pi*(2*(1.7**2*3+(2.7**2-1.7**2)*1.8)+4*(2.25**2*3+(3.2**2-2.25**2)*1.8)+3.2**2*3+7*1.4**2*3+1.7**2*3+4*1.2**2*3),
        "DECK_L1": areas["P05R"]*5,
        "DECK_L2": areas["P06R"]*5,
    }
    for part_id, expected in volumes.items():
        value = parts[part_id].get("体积_mm3", "")
        if not value:
            raise AssertionError(f"{part_id} 缺少三维实体体积，无法核对")
        require_close(float(value), expected, 0.3 if part_id.startswith("DECK_") else 0.01)
    print("P01N 销位及 P02S、P03E、P04、P07R 候选孔通过核对。")
    print("P01N、P03E、P05R、P06R 的俯视轮廓闭合；已有三维体积与图纸一致。")
    print("候选孔和材料强度仍需实物复核，不代表加工批准。")


if __name__ == "__main__":
    main()
