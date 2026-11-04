"""Check the stated v3 tower geometry and budget. Not a substitute for CAD or testing.

Run:  py tools/check_hardware_v3.py   (or python3)
Coordinates: tower centre is the origin, X right, Y back, Z up from base top, mm.
"""

from decimal import Decimal, InvalidOperation
from math import cos, hypot, radians, sin
from pathlib import Path
import re

# ---- design values (keep in sync with docs/硬件方案_v3.md and docs/cad/simulation.js) ----
BAY_ANGLES = [0, 45, 90, 135, 180, 225, 270, 315]   # 8 radial bays; 270 = front (DOCK / shaft)
DOCK_ANGLE = 270
TRAY_L, TRAY_W = 125, 60
CAR_L, CAR_W, CAR_H, TRAY_T = 105, 43, 30, 3
TRAY_R0 = 97                     # stored tray inner end radius
TRAY_R1 = TRAY_R0 + TRAY_L       # 222
END_STOP_R = 226
DECK_EDGE = 250                  # deck half size; ring beam inner face 230
R_CLEAR = 96                     # well clear radius at every deck
PLATE_HALF_L, PLATE_HALF_W = 85, 33
CARRIED_U = (-41, 84)            # tray extent on plate when parked
MOTOR_BOX = ((-84, -32), (-56, -4))   # transfer motor footprint on plate (u, w)
DOWEL_FROM_INNER = 10
FORK_PARK, FORK_REACH, FORK_OFFSET = -31, 107, 36
RAIL_HALF, BLOCK_LEN = 85, 22.5
SUPPORT_PLATE = (-40, 85)        # tray support strips on the plate (u)
CHAMFER = 10                     # tray inner-end corners C10, clear the platform arms
MEMBER_R, MEMBER_ANGLES, MEMBER_ENVELOPE = 140, (22.5, 67.5, 112.5, 202.5), 11
ARM_HALF, ARM_R = 5, (40, 150)   # platform arms 10 wide x 20 tall, radial on member lines
SLOT_HALF, SLOT_LEN = 7, 125     # deck slot for an arm
POCKET_HALF, POCKET = 13, (125, 160)   # deck pocket for bearing / nut / chain
SHAFT_HALF = 38
DECK_Z = (100, 190)
PITCH, FREE = 90, 8
DECK_T, RING_H = 5, 20
ROOF_RING_BOTTOM, ROOF_TOP = 250, 275
STACK_BELOW_PLATE = 27 + 46      # platform bottom 27 below plate top; rotation motor 46 below that
SCREW_Z = (60, 260)
NUT_BELOW_PLATE = 27
Z_LIMIT = (86, 196)


def rot(points, angle):
    c, s = cos(radians(angle)), sin(radians(angle))
    return [(u * c - w * s, u * s + w * c) for u, w in points]


def rect(u0, u1, w0, w1, angle=0):
    return rot([(u0, w0), (u1, w0), (u1, w1), (u0, w1)], angle)


def bay_tray(angle):
    h, c = TRAY_W / 2, CHAMFER
    return rot([(TRAY_R0, -h + c), (TRAY_R0 + c, -h), (TRAY_R1, -h), (TRAY_R1, h), (TRAY_R0 + c, h), (TRAY_R0, h - c)], angle)


def seg_dist(p, a, b):
    (px, py), (ax, ay), (bx, by) = p, a, b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return hypot(px - ax - t * dx, py - ay - t * dy)


def inside(p, poly):
    signs = []
    for i in range(len(poly)):
        (ax, ay), (bx, by) = poly[i], poly[(i + 1) % len(poly)]
        signs.append((bx - ax) * (p[1] - ay) - (by - ay) * (p[0] - ax))
    return all(s > 0 for s in signs) or all(s < 0 for s in signs)


def point_poly(p, poly):
    if inside(p, poly):
        return 0.0
    return min(seg_dist(p, poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly)))


def poly_poly(a, b):
    """Distance between two convex polygons (0 if overlapping)."""
    if any(inside(p, b) for p in a) or any(inside(p, a) for p in b):
        return 0.0
    return min(min(point_poly(p, b) for p in a), min(point_poly(p, a) for p in b))


def storage_angles(layer):
    if layer == 0:
        return [a for a in BAY_ANGLES if a != DOCK_ANGLE]
    return [a for a in BAY_ANGLES if a != DOCK_ANGLE]  # upper layer: DOCK shaft, no bay


def geometry():
    results = []
    trays = {a: bay_tray(a) for a in BAY_ANGLES}

    # 1. Stored trays in the 8 radial bays.
    gap = min(poly_poly(trays[a], trays[b]) for i, a in enumerate(BAY_ANGLES) for b in BAY_ANGLES[i + 1:])
    assert gap >= 15, gap
    inner = min(hypot(x, y) for poly in trays.values() for x, y in poly)
    assert inner >= R_CLEAR + 2, inner
    assert TRAY_R1 < END_STOP_R < DECK_EDGE - 20
    outer = max(max(abs(x), abs(y)) for poly in trays.values() for x, y in poly)
    assert outer <= DECK_EDGE - 20, outer
    results.append(f"8 radial bays: min tray gap {gap:.1f} mm, nearest tray corner r={inner:.1f}, max |x|,|y| {outer:.1f}")

    # 2. Rotation envelope of the transfer plate, carried tray and transfer motor.
    r_plate = hypot(PLATE_HALF_L, PLATE_HALF_W)
    r_tray = max(hypot(u, TRAY_W / 2) for u in CARRIED_U)
    r_motor = max(hypot(u, w) for u in (MOTOR_BOX[0][0], MOTOR_BOX[1][0]) for w in (MOTOR_BOX[0][1], MOTOR_BOX[1][1]))
    envelope = max(r_plate, r_tray, r_motor)
    assert CARRIED_U[1] - CARRIED_U[0] == TRAY_L
    assert envelope <= R_CLEAR - 4, envelope
    assert MOTOR_BOX[1][0] < CARRIED_U[0] - 10, 'motor must stay behind the carried tray'
    results.append(f"rotation envelope R{envelope:.1f} (plate {r_plate:.1f}, tray {r_tray:.1f}, motor {r_motor:.1f}) inside well R{R_CLEAR}")

    # 3. Fork stroke and dowel positions.
    dowel_stored = TRAY_R0 + DOWEL_FROM_INNER
    dowel_carried = CARRIED_U[0] + DOWEL_FROM_INNER
    assert (FORK_REACH, FORK_PARK) == (dowel_stored, dowel_carried)
    dog = (FORK_PARK - FORK_OFFSET, FORK_REACH - FORK_OFFSET)
    dog_limit = RAIL_HALF - BLOCK_LEN / 2
    assert -dog_limit <= dog[0] and dog[1] <= dog_limit, dog
    results.append(f"fork u {FORK_PARK}..{FORK_REACH} (stroke {FORK_REACH - FORK_PARK}); carriage {dog[0]}..{dog[1]} within +/-{dog_limit}")

    # 4. Transfer corridor (union of tray positions) vs neighbouring trays and vertical members.
    corridor_gap = min(
        poly_poly(rect(CARRIED_U[0], TRAY_R1, -TRAY_W / 2, TRAY_W / 2, a), trays[b])
        for a in BAY_ANGLES for b in BAY_ANGLES if a != b)
    assert corridor_gap >= 10, corridor_gap
    members = [(MEMBER_R * cos(radians(a)), MEMBER_R * sin(radians(a))) for a in MEMBER_ANGLES]
    member_gap = min(point_poly(m, trays[a]) for m in members for a in BAY_ANGLES) - MEMBER_ENVELOPE
    member_corridor = min(point_poly(m, rect(CARRIED_U[0], TRAY_R1, -TRAY_W / 2, TRAY_W / 2, a))
                          for m in members for a in BAY_ANGLES) - MEMBER_ENVELOPE
    assert member_gap >= 10 and member_corridor >= 10, (member_gap, member_corridor)
    assert MEMBER_R - MEMBER_ENVELOPE >= R_CLEAR + 20
    slot_gap = min(poly_poly(rect(0, SLOT_LEN, -SLOT_HALF, SLOT_HALF, m), trays[a]) for m in MEMBER_ANGLES for a in BAY_ANGLES)
    pocket_gap = min(poly_poly(rect(*POCKET, -POCKET_HALF, POCKET_HALF, m), trays[a]) for m in MEMBER_ANGLES for a in BAY_ANGLES)
    assert slot_gap >= 3 and pocket_gap >= 5, (slot_gap, pocket_gap)
    assert ARM_HALF <= SLOT_HALF - 2 and ARM_R[1] <= POCKET[1] - 5 and MEMBER_ENVELOPE <= POCKET_HALF - 2
    assert POCKET[0] < MEMBER_R - MEMBER_ENVELOPE and MEMBER_R + MEMBER_ENVELOPE < POCKET[1]
    unchamfered = min(poly_poly(rect(TRAY_R0, TRAY_R1, -TRAY_W / 2, TRAY_W / 2, a), rect(0, SLOT_LEN, -SLOT_HALF, SLOT_HALF, m))
                      for m in MEMBER_ANGLES for a in BAY_ANGLES)
    results.append(f"transfer corridor gap {corridor_gap:.1f}; members r{MEMBER_R} clear trays by {member_gap:.1f}, "
                   f"corridor by {member_corridor:.1f}")
    results.append(f"arm slots +/-{SLOT_HALF} clear chamfered trays by {slot_gap:.1f} mm (without C{CHAMFER}: {unchamfered:.1f}); "
                   f"pockets +/-{POCKET_HALF} by {pocket_gap:.1f}")

    # 5. DOCK shaft on layer 2: cut-out ±38 must not touch SE/SW trays.
    shaft = rect(R_CLEAR - 5, DECK_EDGE + 5, -SHAFT_HALF, SHAFT_HALF, DOCK_ANGLE)
    shaft_gap = min(poly_poly(shaft, trays[a]) for a in storage_angles(1))
    assert shaft_gap >= 5, shaft_gap
    results.append(f"layer-2 DOCK shaft +/-{SHAFT_HALF}: {shaft_gap:.1f} mm from neighbouring trays")

    # 6. Idealised 1-D support while crossing the 11 mm gap (plate strips end u=85, deck starts r=96).
    deck = (R_CLEAR, END_STOP_R)
    worst = None
    for centre10 in range(int((CARRIED_U[0] + TRAY_L / 2) * 10), int((TRAY_R0 + TRAY_L / 2) * 10) + 1):
        c = centre10 / 10
        lo, hi = c - TRAY_L / 2, c + TRAY_L / 2
        contacts = []
        for s0, s1 in (SUPPORT_PLATE, deck):
            a, b = max(lo, s0), min(hi, s1)
            if b > a:
                contacts += [a, b]
        assert contacts and min(contacts) <= c - 15 and max(contacts) >= c + 15, c
        span = max(contacts) - min(contacts)
        worst = span if worst is None else min(worst, span)
    results.append(f"gap crossing {deck[0] - SUPPORT_PLATE[1]} mm: CoG +/-15 mm always within support; min support span {worst:.0f} mm")

    # 7. Heights.
    for layer, z in enumerate(DECK_Z):
        assert z == DECK_Z[0] + layer * PITCH
    fork_top_engaged, dowel_bottom = -1, -5            # relative to deck top
    assert fork_top_engaged - dowel_bottom == 4        # engaged overlap
    assert dowel_bottom - (fork_top_engaged - FREE) == 4  # free clearance
    car_top = DECK_Z[0] + TRAY_T + CAR_H
    strut_bottom = DECK_Z[1] - DECK_T - RING_H
    assert strut_bottom - car_top >= 25, strut_bottom - car_top
    lowest = DECK_Z[0] - FREE - STACK_BELOW_PLATE
    assert lowest >= 15, lowest
    nut = (DECK_Z[0] - FREE - NUT_BELOW_PLATE, DECK_Z[-1] - NUT_BELOW_PLATE + 15)
    assert SCREW_Z[0] <= nut[0] and nut[1] <= SCREW_Z[1] - 10, nut
    assert Z_LIMIT[0] < DECK_Z[0] - FREE and Z_LIMIT[1] > DECK_Z[-1]
    assert Z_LIMIT[1] + TRAY_T + CAR_H < ROOF_RING_BOTTOM
    dock_open = ROOF_RING_BOTTOM - DECK_Z[0]
    results.append(f"decks Z {DECK_Z}; pin overlap 4 / free 4; car-to-strut {strut_bottom - car_top} mm; "
                   f"lowest lift part Z={lowest}; nut Z {nut[0]}..{nut[1]} on screw {SCREW_Z}; DOCK opening {dock_open} mm")

    capacity = [len(storage_angles(layer)) for layer in range(len(DECK_Z))]
    assert capacity == [7, 7]
    results.append(f"capacity: prototype 1 layer {capacity[0]}, plan 2 layers {sum(capacity)}")
    return results


def budget():
    path = Path(__file__).resolve().parent.parent / "docs" / "采购清单_v4.md"
    text = path.read_text(encoding="utf-8-sig")
    totals = {}
    for marker in ("一层样机合计", "第二层扩展包合计"):
        head, text = text.split(f"**{marker}", 1)
        amounts = []
        for line in head.splitlines():
            if not line.startswith("|"):
                continue
            cols = [c.strip() for c in line.strip("|").split("|")]
            if len(cols) != 6:
                continue
            try:
                subtotal = Decimal(cols[4])
            except InvalidOperation:
                continue
            qty = Decimal(re.match(r"\d+(?:\.\d+)?", cols[2]).group())
            unit = Decimal(re.match(r"\d+(?:\.\d+)?", cols[3]).group())
            assert qty * unit == subtotal, (cols[0], qty, unit, subtotal)
            amounts.append(subtotal)
        stated = Decimal(re.match(r"[：:]\s*约?\s*¥\s*([\d,]+\.\d+)", text).group(1).replace(",", ""))
        assert sum(amounts) == stated, (marker, sum(amounts), stated)
        totals[marker] = (len(amounts), sum(amounts))
    return totals


def main():
    for line in geometry():
        print(line)
    names = {"一层样机合计": "batch 1, one-layer prototype", "第二层扩展包合计": "batch 2, layer-2 kit"}
    totals = budget()
    for marker, (count, total) in totals.items():
        print(f"budget {names[marker]}: {count} lines, CNY {total:.2f}")
    print(f"budget two-layer plan: CNY {sum(t for _, t in totals.values()):.2f} before 15% contingency")
    print("Not checked: real 3-D parts, stiffness, friction, motor torque, sensors, circuits, prices or hardware.")


if __name__ == "__main__":
    main()
