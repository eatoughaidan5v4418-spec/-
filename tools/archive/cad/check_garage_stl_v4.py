"""检查打印样件 STL 的网格闭合、尺寸及与装配实体的体积一致性。"""

import argparse
from collections import Counter
import csv
import math
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[3]
DEFAULT = ROOT / "docs" / "archive" / "cad" / "三维装配_v4_干涉调整"
EXPECTED = {
    "01_导杆支撑臂_打印2件.stl": ("LIFT_ARM_22.5", (111, 22, 40)),
    "02_丝杆支撑臂_打印1件.stl": ("LIFT_ARM_112.5", (111, 22, 40)),
    "03_70高底脚_打印4件.stl": ("FOOT_-205_-205", (40, 40, 70)),
    "04_升降电机隔柱16_打印4件.stl": ("LIFT_SPACER_-15.5_-15.5", (8, 8, 16)),
    "05_旋转电机隔柱56_打印4件.stl": ("ROT_SPACER_-15.5_-15.5", (8, 8, 56)),
    "06_转运电机隔柱17_打印3件.stl": ("TRANSFER_SPACER_-11.5_-11.5", (5, 5, 17)),
    "07_KFL支承柱25_打印2件.stl": ("KFL_SPACER_-1", (10, 10, 25)),
    "08_转盘法兰隔套8_打印1件.stl": ("FLANGE_SPACER", (22, 22, 8)),
    "09_拨叉及皮带夹槽_概念试件.stl": ("TRANSFER_FORK", (51, 25.8, 13)),
}


def inspect(path):
    data = path.read_bytes()
    if len(data) < 84:
        raise ValueError(f"STL 过短：{path.name}")
    count = struct.unpack_from("<I", data, 80)[0]
    if count < 4 or len(data) != 84 + count * 50:
        raise ValueError(f"STL 文件长度或三角形数不符：{path.name}")
    edges = Counter()
    minimum = [math.inf] * 3
    maximum = [-math.inf] * 3
    signed_volume = 0.0
    for index in range(count):
        numbers = struct.unpack_from("<12fH", data, 84 + index * 50)
        points = [tuple(numbers[3 + j * 3 : 6 + j * 3]) for j in range(3)]
        if not all(math.isfinite(v) for point in points for v in point):
            raise ValueError(f"STL 含非有限坐标：{path.name}")
        rounded = [tuple(round(v, 4) for v in point) for point in points]
        if len(set(rounded)) != 3:
            raise ValueError(f"STL 含退化三角形：{path.name}")
        for a, b in ((0, 1), (1, 2), (2, 0)):
            edges[tuple(sorted((rounded[a], rounded[b])))] += 1
        for point in points:
            for axis in range(3):
                minimum[axis] = min(minimum[axis], point[axis])
                maximum[axis] = max(maximum[axis], point[axis])
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = points
        signed_volume += (
            ax * (by * cz - bz * cy)
            + ay * (bz * cx - bx * cz)
            + az * (bx * cy - by * cx)
        ) / 6
    bad = sum(1 for count in edges.values() if count != 2)
    if bad:
        raise ValueError(f"STL 网格有 {bad} 条未闭合或非流形边：{path.name}")
    volume = abs(signed_volume)
    if volume <= 0:
        raise ValueError(f"STL 体积为零：{path.name}")
    return tuple(maximum[i] - minimum[i] for i in range(3)), volume, count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", nargs="?", type=Path, default=DEFAULT)
    folder = parser.parse_args().folder
    with (folder / "模型零件与范围.csv").open(encoding="utf-8-sig", newline="") as stream:
        parts = {row["编号"]: row for row in csv.DictReader(stream)}
    for name, (part_id, expected) in EXPECTED.items():
        dims, volume, triangles = inspect(folder / "打印件_STL_待实配" / name)
        for actual, target in zip(dims, expected):
            if not math.isclose(actual, target, abs_tol=0.1):
                raise AssertionError(f"{name} 包络 {dims} 与预期 {expected} 不符")
        source_volume = parts[part_id].get("体积_mm3", "")
        if source_volume and not math.isclose(volume, float(source_volume), rel_tol=0.02, abs_tol=0.2):
            raise AssertionError(f"{name} STL 体积 {volume:.2f} 与 CAD 体积 {source_volume} 不符")
        print(f"{name}: {triangles} 个三角形，闭合，包络 {dims[0]:.2f}×{dims[1]:.2f}×{dims[2]:.2f} mm")
    print("STL 网格检查通过；不代表材料强度、配合公差或实际打印已验证。")


if __name__ == "__main__":
    main()
