"""核对三维装配检查输出中的关键尺寸与相交体积，不替代实际装配。"""

import argparse
import csv
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT = ROOT / "docs" / "cad" / "三维装配_初步校核"


def csv_rows(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def close(actual, expected, tolerance=0.001):
    if not math.isclose(actual, expected, abs_tol=tolerance, rel_tol=0):
        raise AssertionError(f"{actual} 不等于预期 {expected}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", nargs="?", type=Path, default=DEFAULT)
    folder = parser.parse_args().folder
    summary = json.loads((folder / "检查统计.json").read_text(encoding="utf-8-sig"))
    parts_list = csv_rows(folder / "模型零件与范围.csv")
    parts = {part["编号"]: part for part in parts_list}
    assert len(parts) == len(parts_list) == summary["实体数"] == 107

    def z(part_id, field):
        return float(parts[part_id][field + "Z_mm"])

    for motor in ("LIFT_MOTOR_SHAFT", "ROT_MOTOR_SHAFT"):
        close(z(motor, "最大") - z(motor, "最小"), 67)
    close(z("ROOF", "最大") - z("ROOF", "最小"), 5)
    close(z("ROOF", "最小") - z("KFL_TOP", "最大"), 10)
    close(z("LIFT_MOTOR_SHAFT", "最大") - z("LEAD_SCREW", "最小"), 47)
    close(z("ROT_MOTOR_SHAFT", "最大") - z("CENTER_TRAY", "最大"), 37)

    clashes = csv_rows(folder / "基准工况_实体相交.csv")
    clash_by_pair = {frozenset((row["零件A"], row["零件B"])): row for row in clashes}
    assert len(clashes) == summary["基准相交对"]
    for a, b, length in (
        ("LIFT_MOTOR_SHAFT", "LEAD_SCREW", 47),
        ("ROT_MOTOR_SHAFT", "LIFT_DISC", 5),
        ("ROT_MOTOR_SHAFT", "TRANSFER_PLATE", 3),
        ("ROT_MOTOR_SHAFT", "TRANSFER_RAIL", 5),
        ("ROT_MOTOR_SHAFT", "CENTER_TRAY", 3),
        ("ROT_MOTOR_SHAFT", "CENTER_CAR", 30),
    ):
        row = clash_by_pair[frozenset((a, b))]
        close(float(row["相交体积_mm3"]), math.pi * 2.5**2 * length, 0.001)
    for column in range(1, 5):
        for deck in ("DECK_L1", "DECK_L2"):
            row = clash_by_pair[frozenset((f"COLUMN_{column}", deck))]
            close(float(row["相交体积_mm3"]), 20 * 20 * 5)

    mounting = csv_rows(folder / "候选安装孔_名义贯通检查.csv")
    assert len(mounting) == summary["候选孔探针数"] == 20
    assert all(row["结果"] == "名义贯通" and not row["错误"] for row in mounting)
    poses = csv_rows(folder / "运动采样_覆盖情况.csv")
    assert len(poses) == summary["离散工况数"] == 33
    assert all(int(row["检查错误"]) == 0 for row in poses)
    assert summary["检查错误数"] == summary["探针阻挡或错误数"] == 0
    assert summary["恢复基准最大偏差_mm"] < 0.0001
    samples = csv_rows(folder / "运动采样_实体相交.csv")
    assert len(samples) == summary["采样相交记录数"]

    dwg = folder / "车库_两层三维装配_一层载盘.dwg"
    sat = folder / "车库_两层三维实体_一层载盘.SAT"
    assert dwg.stat().st_size > 50000
    assert sat.stat().st_size > 50000
    assert sat.read_bytes().startswith(b"700 ")
    print("输出核对通过：107 个实体、20 个候选孔探针、33 个采样工况。")
    print("已复核双电机 67 mm、顶板 5 mm、两轴重叠与甲板角部相交体积。")
    print("此脚本核对导出结果；实体文件重新打开和 SAT 导入需另运行 PowerShell 检查。")


if __name__ == "__main__":
    main()
