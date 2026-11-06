"""独立复核 v7 夹带、双向止推及可调限位的名义几何和采样结果。"""

import argparse
import csv
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT = ROOT / "docs" / "cad" / "三维装配_v7_加厚夹带"


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

    def coord(part, edge, axis):
        return float(parts[part][edge + axis + "_mm"])

    for shaft in ("LIFT_MOTOR_SHAFT", "ROT_MOTOR_SHAFT"):
        close(z(shaft, "最大") - z(shaft, "最小"), 24)
    close(z("LEAD_SCREW", "最大") - z("LEAD_SCREW", "最小"), 200)
    close(z("ROOF", "最大") - z("ROOF", "最小"), 5)
    for x in (-30, 30):
        for y in (-15.5, 15.5):
            bolt = f"LIFT_BRACKET_FOOT_{x}_{y}_SHAFT"
            close(z(bolt, "最大") - z(bolt, "最小"), 12)
    close(z("LEAD_SCREW", "最小") - z("LIFT_MOTOR_SHAFT", "最大"), 4)
    close(z("LIFT_MOTOR_SHAFT", "最大") - z("LIFT_COUPLER", "最小"), 10)
    close(z("LIFT_COUPLER", "最大") - z("LEAD_SCREW", "最小"), 11)
    close(z("TRANSFER_PLATE", "最小") - z("ROT_MOTOR_SHAFT", "最大"), 4)
    close(z("CENTER_TRAY", "最小") - z("ROT_MOTOR_SHAFT", "最大"), 18)
    close(z("LIFT_MOTOR_BODY", "最小") - z("BASE", "最大"), 0)
    close(z("ROT_MOTOR_BODY", "最小") - 14 - z("BASE", "最大"), 4)
    close(z("ROOF", "最小") - z("KFL_TOP", "最大"), 22)
    for end in ("TOP", "BOTTOM"):
        close(z("THRUST_BEARING_"+end, "最大")-z("THRUST_BEARING_"+end, "最小"), 5)
        close(coord("THRUST_BEARING_"+end, "最大", "X")-coord("THRUST_BEARING_"+end, "最小", "X"), 16, 0.002)
    for position in ("TOP_1", "TOP_2", "BOTTOM_1", "BOTTOM_2"):
        close(z("T8_JAM_"+position, "最大")-z("T8_JAM_"+position, "最小"), 6)
    close(z("THRUST_BEARING_TOP", "最小"), z("THRUST_SEAT_TOP_2", "最大"))
    close(z("THRUST_BEARING_BOTTOM", "最大"), z("THRUST_SEAT_BOTTOM_1", "最小"))
    close(z("T8_JAM_TOP_2", "最大")+1, z("LEAD_SCREW", "最大"))
    close(z("ROOF", "最小")-z("T8_JAM_TOP_2", "最大"), 3)
    close(z("T8_JAM_BOTTOM_1", "最小")-(z("LIFT_NUT_FLANGE", "最大")+94), 5)
    close(z("LIMIT_LEVER_LOW", "最大")-(z("LM8LUU_1", "最小")-10), 0)
    close(z("LIMIT_LEVER_HIGH", "最小")-(z("LIFT_ARM_22.5", "最大")+92), 0)
    close(coord("BELT_END_OVERLAP", "最大", "X")-coord("BELT_END_OVERLAP", "最小", "X"), 6)
    close(coord("BELT_NEAR", "最大", "Y"), coord("BELT_END_OVERLAP", "最小", "Y"))
    close(coord("BELT_END_OVERLAP", "最大", "Y"), coord("BELT_PRESS_PLATE", "最小", "Y"))
    close(z("TRANSFER_FORK", "最小")-z("TRANSFER_PLATE", "最大"), 0.5)
    # 在越程 -2 / 140 处，以完整 2 mm 背壁的最近角点计算与假设 R6.5 带轮的平面间隙。
    jaw_x0 = coord("BELT_END_OVERLAP", "最小", "X")
    jaw_x1 = coord("BELT_END_OVERLAP", "最大", "X")
    close(jaw_x0, -65.5)
    close(jaw_x1, -59.5)
    wheel_y = -23.5
    wall_outer_y = -19.0
    wheel_clearances = (
        math.hypot(jaw_x0 - 2 - (-74), wall_outer_y - wheel_y) - 6.5,
        math.hypot(87.5 - (jaw_x1 + 140), wall_outer_y - wheel_y) - 6.5,
    )
    if min(wheel_clearances) < 1.4:
        raise AssertionError(f"夹壁与带轮名义间隙不足：{wheel_clearances}")
    sweep = rows(folder / "夹带结构_连续包络检查.csv")
    if {r["检查"] for r in sweep} != {"2mm背壁", "1mm挡边", "电机轮连续间隙", "惰轮连续间隙"}:
        raise AssertionError("夹带座材料或连续行程余量检查不完整")
    if not all(r["结果"] == "通过" for r in sweep):
        raise AssertionError("夹带座材料或连续包络检查未通过")

    # 24A 短轴尾端 18 mm 为扁位；夹持位置按名义值核对。
    lift_flat_start = z("LIFT_MOTOR_SHAFT", "最大") - 18
    rot_flat_start = z("ROT_MOTOR_SHAFT", "最大") - 18
    if z("LIFT_COUPLER", "最小") < lift_flat_start or z("FLANGE_HUB", "最小") < rot_flat_start:
        raise AssertionError("42 电机轴夹持位置未完整落在资料所示扁位")
    close(z("FLANGE_HUB", "最大") - z("FLANGE_HUB", "最小"), 10)

    # 停放托盘整体外移3，销保持r107；半径下界可覆盖任何相对转角。
    close(coord("CENTER_TRAY", "最小", "X"), -38)
    close(coord("CENTER_TRAY", "最大", "X"), 87)
    close(coord("CENTER_TRAY", "最大", "X") - coord("STRIP_-26.5", "最大", "X"), 8.5)
    close(coord("CENTER_TRAY", "最大", "X") - coord("STRIP_28.5", "最大", "X"), 2)
    close(coord("TRAY_L2_0", "最小", "X"), 100)
    close(coord("TRAY_L2_0", "最大", "X"), 225)
    close((coord("CENTER_PIN", "最小", "X") + coord("CENTER_PIN", "最大", "X"))/2, -31)
    # 惰轮外侧皮带圆环为保守轮缘包络；与 R102 井口的径向距离是名义间隙。
    belt_radius = math.hypot(87.5, 23.5) + 7.9
    clearance = 102 - belt_radius
    if not 3.49 < clearance < 3.51:
        raise AssertionError(f"井口径向间隙不符：{clearance:.4f}")
    strip_end = coord("STRIP_-26.5", "最大", "X")
    strip_inside_y = coord("STRIP_-26.5", "最大", "Y")
    wrap_gap = math.hypot(87.5 - strip_end, -23.5 - strip_inside_y) - 7.9
    straight_gap = coord("STRIP_-26.5", "最小", "Y") - coord("BELT_FAR", "最大", "Y")
    if min(wrap_gap, straight_gap) < 0.999:
        raise AssertionError(f"负侧支撑条与皮带间隙不足：{wrap_gap:.3f}, {straight_gap:.3f}")
    tray_clearance = 100 - belt_radius
    if tray_clearance < 1.49:
        raise AssertionError(f"惰轮带包络到停放托盘的径向余量不足：{tray_clearance:.4f}")
    motor_radius = max(math.hypot(x, y)
                       for x in (coord("TRANSFER_MOTOR_BODY", "最小", "X"), coord("TRANSFER_MOTOR_BODY", "最大", "X"))
                       for y in (coord("TRANSFER_MOTOR_BODY", "最小", "Y"), coord("TRANSFER_MOTOR_BODY", "最大", "Y")))
    if 100 - motor_radius < 4:
        raise AssertionError(f"电机包络到停放托盘的径向余量不足：{100-motor_radius:.4f}")
    if summary["基准相交对"] or summary["采样相交记录数"] or summary["推拉相交记录数"]:
        raise AssertionError("存在实体相交，需查看相应 CSV")
    if summary["检查错误数"] or summary["探针阻挡或错误数"]:
        raise AssertionError("存在检查错误或孔位探针被阻挡")
    if summary["拨叉越程相交记录数"]:
        raise AssertionError("拨叉越程中存在非预期相交")
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
        for height in (86, 88, 90, 92, 100, 130, 182, 190, 192, 194):
            if (height, 0) not in samples:
                raise AssertionError(f"缺少升降工况 Z={height}")
        for height in (86, 92, 130, 190, 192, 194):
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
    stops = rows(folder / "限位_机械止挡检测.csv")
    if len(stops) != 2 or any(r["临界前相交"] != "False" or r["临界后相交"] != "True" for r in stops):
        raise AssertionError("上下止挡的几何接触边界检查未通过")
    contacts = rows(folder / "限位_预期摇臂接触.csv")
    expected_contacts = {("LIMIT_LEVER_LOW", "LM8LUU_1"), ("LIMIT_LEVER_HIGH", "LIFT_ARM_22.5")}
    if not contacts or any((r["零件A"], r["零件B"]) not in expected_contacts for r in contacts):
        raise AssertionError("限位接触清单缺失或包含未授权的零件对")
    if len(contacts) != summary["限位预期接触记录数"]:
        raise AssertionError("限位接触记录数量不符")
    fork_stops = rows(folder / "拨叉_机械止挡检测.csv")
    if len(fork_stops) != 2 or any(r["临界前相交"] != "False" or r["临界后相交"] != "True" for r in fork_stops):
        raise AssertionError("拨叉止挡的几何边界检查未通过")
    overrun = rows(folder / "拨叉_越程覆盖情况.csv")
    required_strokes = {-2, -1.5, -1, -0.5, 0, 138, 138.5, 139, 139.5, 140}
    for mode in ("载盘", "空叉"):
        if {float(r["行程_mm"]) for r in overrun if r["工况"] == mode} != required_strokes:
            raise AssertionError(f"{mode}拨叉越程采样不完整")
    if len(overrun) != 20 or len(overrun) != summary["拨叉越程工况数"]:
        raise AssertionError("拨叉越程数量不符")
    if any(int(r["相交实体对"]) or int(r["检查错误"]) for r in overrun):
        raise AssertionError("拨叉越程采样出现未解决相交或检查错误")
    if rows(folder / "拨叉_越程实体相交.csv"):
        raise AssertionError("拨叉越程相交表非空")
    fork_contacts = rows(folder / "拨叉_预期摇臂接触.csv")
    allowed = {frozenset(("FORK_LIMIT_LEVER_IN", "TRANSFER_SLIDER")),
               frozenset(("FORK_LIMIT_LEVER_OUT", "TRANSFER_SLIDER"))}
    found = {frozenset((r["零件A"], r["零件B"])) for r in fork_contacts}
    if found != allowed or len(fork_contacts) != summary["拨叉预期接触记录数"]:
        raise AssertionError("拨叉预期接触缺失或包含其他零件")
    close(coord("TRANSFER_SLIDER", "最小", "X")-coord("FORK_LIMIT_LEVER_IN", "最大", "X"), 0.5)
    close(coord("FORK_LIMIT_LEVER_OUT", "最小", "X")-(coord("TRANSFER_SLIDER", "最大", "X")+138), 0.5)
    print(f"{len(parts)} 个实体、{len(probes)} 个孔位探针、{len(poses)} 个升降旋转和 {len(transfers)} 个推拉采样通过。")
    print(f"升降两轴端相距 4 mm，旋转轴距转运板 4 mm；带轮外包络距井口约 {clearance:.2f} mm。")
    print(f"停放托盘内端 r100、销 r107；皮带外包络至托盘内端径向余量约 {tray_clearance:.2f} mm。")
    print(f"负侧支撑条至绕轮带与直线带的名义间隙 {wrap_gap:.2f}/{straight_gap:.2f} mm。")
    print(f"止挡几何边界 Z=86/194；另记录 {len(contacts)} 处预期摇臂接触，未验证摇臂变形和受力。")
    print(f"拨叉止挡几何边界 -2/140 mm；{len(overrun)} 个越程采样、{len(fork_contacts)} 处预期摇臂接触。")
    print(f"2 mm 背壁、1 mm 挡边已核实；两端轮与背壁名义间隙 {wheel_clearances[0]:.2f}/{wheel_clearances[1]:.2f} mm，连续行程余量不小于 0.99 mm。")
    print("这是按模型几何的名义检查，不证明实际零件、强度或全装配连续行程已通过。")


if __name__ == "__main__":
    main()
