"""独立复核 v4 已导出的名义尺寸、离散运动采样和关键净空。"""

import argparse
import csv
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
DEFAULT = ROOT / "docs" / "archive" / "cad" / "三维装配_v4_干涉调整"


def rows(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def close(actual, expected, tolerance=0.001):
    if not math.isclose(actual, expected, abs_tol=tolerance, rel_tol=0):
        raise AssertionError(f"实际 {actual:.6f}，预期 {expected:.6f}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", nargs="?", type=Path, default=DEFAULT)
    parser.add_argument("--fast", action="store_true", help="允许快速试验结果")
    args = parser.parse_args()
    folder = args.folder
    summary = json.loads((folder / "检查统计.json").read_text(encoding="utf-8-sig"))
    if not args.fast and summary["采样模式"] != "完整离散采样":
        raise AssertionError("需要完整离散采样，不能使用快速试验结果")
    parts_list = rows(folder / "模型零件与范围.csv")
    parts = {part["编号"]: part for part in parts_list}
    if len(parts) != len(parts_list) or len(parts) != summary["实体数"]:
        raise AssertionError("实体编号重复或数量不符")

    def z(part, edge):
        return float(parts[part][edge + "Z_mm"])

    for shaft in ("LIFT_MOTOR_SHAFT", "ROT_MOTOR_SHAFT"):
        close(z(shaft, "最大") - z(shaft, "最小"), 67)
    close(z("LEAD_SCREW", "最大") - z("LEAD_SCREW", "最小"), 200)
    close(z("ROOF", "最大") - z("ROOF", "最小"), 5)
    close(z("LEAD_SCREW", "最小") - z("LIFT_MOTOR_SHAFT", "最大"), 5)
    close(z("LIFT_MOTOR_SHAFT", "最大") - z("LIFT_COUPLER", "最小"), 10)
    close(z("LIFT_COUPLER", "最大") - z("LEAD_SCREW", "最小"), 10)
    close(z("TRANSFER_PLATE", "最小") - z("ROT_MOTOR_SHAFT", "最大"), 2)
    close(z("CENTER_TRAY", "最小") - z("ROT_MOTOR_SHAFT", "最大"), 16)
    close(z("FOOT_-205_-205", "最大") - z("FOOT_-205_-205", "最小"), 70)
    close(z("LIFT_MOTOR_BODY", "最小") - z("FOOT_-205_-205", "最小"), 14)
    close(z("ROOF", "最小") - z("KFL_TOP", "最大"), 25)
    close(z("LEAD_STOP_COLLAR", "最小"), z("KFL_TOP", "最大"))
    close(z("LEAD_STOP_COLLAR", "最大"), z("LEAD_SCREW", "最大"))

    # 42 电机尾端 20 mm 为扁位。名义法兰轴套/升降联轴器夹持段均落在该范围内。
    lift_flat_start = z("LIFT_MOTOR_SHAFT", "最大") - 20
    rot_flat_start = z("ROT_MOTOR_SHAFT", "最大") - 20
    if z("LIFT_COUPLER", "最小") < lift_flat_start or z("FLANGE_HUB", "最小") < rot_flat_start:
        raise AssertionError("42 电机轴夹持位置未完整落在资料所示扁位")
    close(z("FLANGE_HUB", "最大") - z("FLANGE_HUB", "最小"), 10)

    # 惰轮外侧皮带圆环为保守轮缘包络；与 R96 井口的径向距离是名义间隙。
    belt_radius = math.hypot(83, 23.5) + 7.9
    clearance = 96 - belt_radius
    if not 1.8 < clearance < 1.9:
        raise AssertionError(f"井口径向间隙不符：{clearance:.4f}")
    if summary["基准相交对"] or summary["采样相交记录数"] or summary["推拉相交记录数"]:
        raise AssertionError("存在实体相交，需查看相应 CSV")
    if summary["检查错误数"] or summary["探针阻挡或错误数"]:
        raise AssertionError("存在检查错误或孔位探针被阻挡")
    if summary["恢复基准最大偏差_mm"] > 0.0001:
        raise AssertionError("采样后模型没有恢复至基准位置")
    probes = rows(folder / "候选安装孔_名义贯通检查.csv")
    if len(probes) != summary["候选孔探针数"] or not all(r["结果"] == "名义贯通" for r in probes):
        raise AssertionError("孔位检查记录不完整")
    poses = rows(folder / "运动采样_覆盖情况.csv")
    transfers = rows(folder / "托盘推拉_覆盖情况.csv")
    if len(poses) != summary["离散工况数"] or len(transfers) != summary["推拉工况数"]:
        raise AssertionError("运动采样记录数量不符")
    if not all(int(r["相交实体对"]) == 0 and int(r["检查错误"]) == 0 for r in poses + transfers):
        raise AssertionError("运动采样有相交或错误")
    if not args.fast:
        samples = {(int(r["升降高度_mm"]), int(r["旋转角_deg"])) for r in poses}
        for height in (86, 92, 100, 130, 182, 190, 196):
            if (height, 0) not in samples:
                raise AssertionError(f"缺少升降工况 Z={height}")
        for height in (92, 130, 190):
            for angle in range(15, 316, 15):
                if (height, angle) not in samples:
                    raise AssertionError(f"缺少旋转工况 Z={height}, θ={angle}")
        for mode in ("一层载盘推拉", "一层空叉推拉"):
            covered = {int(r["行程_mm"]) for r in transfers if r["工况"] == mode}
            if covered != set(range(0, 139, 2)):
                raise AssertionError(f"{mode} 行程覆盖不完整")
    for name in ("基准工况_实体相交.csv", "运动采样_实体相交.csv", "托盘推拉_实体相交.csv"):
        if rows(folder / name):
            raise AssertionError(f"{name} 不是空结果")
    print(f"{len(parts)} 个实体、{len(probes)} 个孔位探针、{len(poses)} 个升降旋转和 {len(transfers)} 个推拉采样通过。")
    print(f"升降两轴端相距 5 mm，旋转轴距转运板 2 mm；带轮外包络距井口约 {clearance:.2f} mm。")
    print("这是按模型几何的名义检查，不证明实际零件、强度或连续行程已通过。")


if __name__ == "__main__":
    main()
