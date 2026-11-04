"""Check the stated 2-D tray geometry and budget, not a substitute for CAD or testing."""

from collections import deque
from decimal import Decimal, InvalidOperation
from itertools import permutations
from math import hypot
from pathlib import Path
import re


POINTS = ((75, 45), (225, 45), (75, 135), (225, 135))
ADJACENT = ((1, 2), (0, 3), (0, 3), (1, 2))
TRAY_X, TRAY_Y = 140, 80
DOCK = 3


def rect(center):
    x, y = center
    return (x - TRAY_X / 2, x + TRAY_X / 2, y - TRAY_Y / 2, y + TRAY_Y / 2)


def separation(a, b):
    """Distance between two closed axis-aligned rectangles."""
    dx = max(a[0] - b[1], b[0] - a[1], 0)
    dy = max(a[2] - b[3], b[2] - a[3], 0)
    return hypot(dx, dy)


def overlaps(a, b):
    return a[0] < b[1] and b[0] < a[1] and a[2] < b[3] and b[2] < a[3]


def successors(state):
    empty = state.index(0)
    for src in ADJACENT[empty]:
        moved = list(state)
        moved[src], moved[empty] = moved[empty], moved[src]
        yield tuple(moved), src, empty


def distance_to_dock(state, target):
    queue = deque([(state, 0)])
    seen = {state}
    while queue:
        current, steps = queue.popleft()
        if current[DOCK] == target:
            return steps
        for nxt, _, _ in successors(current):
            if nxt not in seen:
                seen.add(nxt)
                queue.append((nxt, steps + 1))
    raise AssertionError(f"tray {target} cannot reach dock from {state}")


def main():
    states = list(permutations((0, 1, 2, 3)))
    shortest = [distance_to_dock(state, target) for state in states for target in (1, 2, 3)]
    assert len(shortest) == 72

    min_clearance = float("inf")
    transition_count = 0
    for state in states:
        for _, src, dst in successors(state):
            transition_count += 1
            x0, y0 = POINTS[src]
            x1, y1 = POINTS[dst]
            steps = abs(x1 - x0) + abs(y1 - y0)
            for i in range(steps + 1):
                t = i / steps
                moving = rect((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
                for other, occupant in enumerate(state):
                    if occupant and other != src:
                        stationary = rect(POINTS[other])
                        assert not overlaps(moving, stationary), (state, src, dst, i, other)
                        min_clearance = min(min_clearance, separation(moving, stationary))

    handoffs = 0
    for state in states:
        if state[DOCK] == 0:
            continue
        handoffs += 1
        for x in range(225, 401):
            moving = rect((x, 135))
            for other, occupant in enumerate(state):
                if occupant and other != DOCK:
                    assert not overlaps(moving, rect(POINTS[other])), (state, x, other)

    # Ideal 1-D support model: fixed flat floor to x=320; roller centre lines
    # at 340, 380, 420, 460. Ignore compliance, holes, roller radius and friction.
    # Require each roller centre to lie 5 mm inside the tray; model centre of
    # gravity within +/-20 mm of tray centre, along the transfer direction.
    rollers = (340, 380, 420, 460)
    for center in range(225, 401):
        left, right = center - 70, center + 70
        support = []
        if left <= 320 and right >= 0:
            support += [max(left, 0), min(right, 320)]
        support += [x for x in rollers if left + 5 <= x <= right - 5]
        assert support and min(support) <= center - 20 and max(support) >= center + 20, center

    assert 280 - 22.5 >= 225 + 10
    assert 150 - 22.5 >= 90 + 10
    assert (420 - 20) - (200 + 175) == 25
    assert (420 + 37) <= 510 and (70 - 37) >= 10
    assert 90 <= 70 + 60 - 8 and 420 + 60 + 8 <= 540
    assert 205 - 4 - 180 == 21

    budget_path = Path(__file__).resolve().parent.parent / "docs" / "采购清单_v3.md"
    budget_text = budget_path.read_text(encoding="utf-8-sig").split("**表内合计", 1)[0]
    amounts = []
    for line in budget_text.splitlines():
        if not line.startswith("|"):
            continue
        columns = [part.strip() for part in line.strip("|").split("|")]
        if len(columns) != 6:
            continue
        try:
            subtotal = Decimal(columns[4])
            qty = Decimal(re.match(r"\d+(?:\.\d+)?", columns[2]).group())
            unit = Decimal(re.match(r"\d+(?:\.\d+)?", columns[3]).group())
            assert qty * unit == subtotal, (columns[0], qty, unit, subtotal)
            amounts.append(subtotal)
        except InvalidOperation:
            pass
    assert len(amounts) == 41, len(amounts)
    assert sum(amounts) == Decimal("3578.48"), sum(amounts)

    print(f"72 starting-state/target checks passed; max shortest path: {max(shortest)} moves")
    print(f"{transition_count} legal slides sampled at 1 mm; minimum tray clearance: {min_clearance:g} mm")
    print(f"{handoffs} loaded-dock states; transfer sampled at 1 mm without tray overlap")
    print("Idealised transfer support and 20 mm longitudinal COM offset: passed")
    print("Guide travel, height envelope, lift axes and screw extents: passed")
    print(f"41 budget lines: CNY {sum(amounts):.2f}")
    print("Not checked: real 3-D parts, gripper, stress, friction, sensors, circuits, prices or hardware.")


if __name__ == "__main__":
    main()
