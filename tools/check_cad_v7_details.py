"""核对 v7 安装详图中关键二维实体与三维装配的名义尺寸。"""

import argparse
import csv
from pathlib import Path

from check_cad_drawings_v3 import edge, entities, field, point


ROOT = Path(__file__).resolve().parents[1]


def drawing(folder, prefix):
    matches = list(folder.glob(prefix + "*.dxf"))
    if len(matches) != 1:
        raise AssertionError(f"{prefix}: 预期一张 DXF，实际 {len(matches)}")
    return entities(matches[0])


def close(a, b, tol=0.002):
    return abs(a-b) <= tol


def has_line(items, a, b, layer):
    for ent in items:
        if ent["type"] != "LINE" or field(ent, 8) != layer:
            continue
        p, q = edge(ent)
        if ((all(close(p[i], a[i]) and close(q[i], b[i]) for i in (0, 1))) or
                (all(close(q[i], a[i]) and close(p[i], b[i]) for i in (0, 1)))):
            return True
    return False


def rectangle(items, x, y, w, h, layer="OUTLINE"):
    pts = ((x, y), (x+w, y), (x+w, y+h), (x, y+h))
    if not all(has_line(items, pts[i], pts[(i+1)%4], layer) for i in range(4)):
        raise AssertionError(f"缺少矩形 {x}, {y}, {w}, {h}, {layer}")


def has_round(items, kind, x, y, radius, layer):
    return any(ent["type"] == kind and field(ent, 8) == layer and
               all(close(a, b) for a, b in zip(point(ent, 10, 20), (x, y))) and
               close(float(field(ent, 40)), radius) for ent in items)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("drawings", nargs="?", type=Path, default=ROOT/"docs/cad/图纸_v7_加厚夹带")
    parser.add_argument("assembly", nargs="?", type=Path, default=ROOT/"docs/cad/三维装配_v7_加厚夹带")
    args = parser.parse_args()
    with (args.assembly/"模型零件与范围.csv").open(encoding="utf-8-sig", newline="") as stream:
        parts = {r["编号"]: r for r in csv.DictReader(stream)}

    def extent(name, edge_name, axis):
        return float(parts[name][edge_name+axis+"_mm"])

    # A01：上止推环的外径和高度、上方锁紧螺母高度对应装配。
    a01 = drawing(args.drawings, "A01_")
    for part, inner in (("THRUST_BEARING_TOP", 4.05), ("T8_JAM_TOP_2", 4.05)):
        outer = (extent(part, "最大", "X")-extent(part, "最小", "X"))/2
        z0, z1 = extent(part, "最小", "Z"), extent(part, "最大", "Z")
        rectangle(a01, 100+inner*4, 45+(z0-210)*4, (outer-inner)*4, (z1-z0)*4,
                  "OUTLINE" if part.startswith("THRUST") else "REFERENCE")

    # A02：同一截面按图中 10:1 比例映射三维皮带包络、搭接端和压片。
    a02 = drawing(args.drawings, "A02_")
    for part, layer in (("BELT_NEAR", "REFERENCE"), ("BELT_END_OVERLAP", "REFERENCE"),
                        ("BELT_PRESS_PLATE", "OUTLINE")):
        y0, y1 = extent(part, "最小", "Y"), extent(part, "最大", "Y")
        z0, z1 = extent(part, "最小", "Z"), extent(part, "最大", "Z")
        rectangle(a02, 35+(y0+19)*10, 130+(z0-100+10.5)*10,
                  (y1-y0)*10, (z1-z0)*10, layer)
    rectangle(a02, 35, 139, 20, 72)  # 整块 2 mm 夹持背壁
    rectangle(a02, 35, 130, 49, 10)  # 1 mm 挡边
    for x in (240, 330):
        if not has_round(a02, "CIRCLE", x, 232.5, 10, "CENTER"):
            raise AssertionError("A02 压紧螺钉位置不符")

    # A03：安装长孔端部圆弧与 Ø2.4、孔距6.5、移动±1.5一致。
    a03 = drawing(args.drawings, "A03_")
    for y in (224.6, 236.6, 250.6, 262.6):
        if not has_round(a03, "ARC", 245, y, 4.8, "REFERENCE"):
            raise AssertionError("A03 可调长孔端部不符")

    a04 = drawing(args.drawings, "A04_")
    for part, y in (("STRIP_-26.5", 240), ("STRIP_28.5", 145)):
        length = extent(part, "最大", "X")-extent(part, "最小", "X")
        width = extent(part, "最大", "Y")-extent(part, "最小", "Y")
        rectangle(a04, 40, y, length, width)

    a05 = drawing(args.drawings, "A05_")
    for x in (105.75, 138.25):
        if not has_round(a05, "CIRCLE", x, 240, 5.5, "REFERENCE"):
            raise AssertionError("A05 拨叉限位座固定孔位置不符")
    for part in ("FORK_LIMIT_BRACKET_IN", "FORK_LIMIT_BRACKET_OUT"):
        width = extent(part, "最大", "X")-extent(part, "最小", "X")
        if not close(width, 16.8):
            raise AssertionError("拨叉限位座宽度与 A05 不符")
    print("A01～A05 关键截面、支撑条及限位孔与装配名义尺寸一致；实际结构和受力未验证。")


if __name__ == "__main__":
    main()
