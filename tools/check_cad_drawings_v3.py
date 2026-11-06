"""核对 AutoCAD 导出的 v3 DXF 草案：外形尺寸、闭合性、销槽和定位销参考。

用法：py tools/check_cad_drawings_v3.py [图纸目录]
只检查图中已表达的几何；不证明零件可加工、可装配或安全。
"""
from collections import Counter, defaultdict
from math import cos, radians, sin
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parent.parent
DEFAULT = ROOT / "docs" / "archive" / "cad" / "图纸_v3_草案"
PARTS = {
    "P01": (125, 60, 3),
    "P02": (520, 520, 6),
    "P03": (170, 66, 3),
    "P04": (500, 500, 3),
    "P05": (500, 500, 5),
    "P06": (500, 500, 5),
}
EPS = 0.0001


def entities(path):
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    assert len(lines) % 2 == 0, f"DXF 键值对不完整: {path}"
    active, item, result = False, None, []
    for code, value in zip(lines[::2], lines[1::2]):
        code, value = code.strip(), value.strip()
        if code == "2" and value == "ENTITIES" and not active:
            active = True
            continue
        if not active:
            continue
        if code == "0":
            if item:
                result.append(item)
            if value == "ENDSEC":
                return result
            item = {"type": value, "groups": defaultdict(list)}
        elif item:
            item["groups"][code].append(value)
    raise AssertionError(f"缺少完整 ENTITIES: {path}")


def field(entity, code, default=None):
    values = entity["groups"].get(str(code), [])
    return values[0] if values else default


def point(entity, xcode, ycode):
    return float(field(entity, xcode)), float(field(entity, ycode))


def near(a, b):
    return abs(a - b) < EPS


def near_point(a, b):
    return near(a[0], b[0]) and near(a[1], b[1])


def edge(entity):
    if entity["type"] == "LINE":
        return point(entity, 10, 20), point(entity, 11, 21)
    if entity["type"] == "ARC":
        cx, cy = point(entity, 10, 20)
        r = float(field(entity, 40))
        a, b = radians(float(field(entity, 50))), radians(float(field(entity, 51)))
        return (cx + r * cos(a), cy + r * sin(a)), (cx + r * cos(b), cy + r * sin(b))
    raise AssertionError("不是边")


def check_closed(edges, expected_components, part):
    # DXF 写入精度高于 0.0001 mm，量化后检查每个端点恰好连接两条边。
    def key(p):
        return tuple(round(v, 4) for v in p)

    adjacency = defaultdict(list)
    for p, q in edges:
        p, q = key(p), key(q)
        assert p != q, f"{part}: 零长度边"
        adjacency[p].append(q)
        adjacency[q].append(p)
    broken = [p for p, neighbours in adjacency.items() if len(neighbours) != 2]
    assert not broken, f"{part}: 轮廓未闭合或有重复边：{broken[:5]}"
    unseen = set(adjacency)
    components = 0
    while unseen:
        components += 1
        stack = [unseen.pop()]
        while stack:
            for neighbour in adjacency[stack.pop()]:
                if neighbour in unseen:
                    unseen.remove(neighbour)
                    stack.append(neighbour)
    assert components == expected_components, f"{part}: 应有 {expected_components} 个轮廓，实际 {components}"


def has_edge(edges, p, q):
    return any((near_point(a, p) and near_point(b, q)) or
               (near_point(a, q) and near_point(b, p)) for a, b in edges)


def check(path, code, length, width, thickness):
    items = entities(path)
    dims = [e for e in items if e["type"] == "DIMENSION" and field(e, 8) == "DIMENSIONS"]
    assert len(dims) == 2, f"{code}: 需要两个实体尺寸标注"
    hdim = next(e for e in dims if near(float(field(e, 50, "0")), 0))
    vdim = next(e for e in dims if near(float(field(e, 50, "0")), 90))
    assert near(float(field(hdim, 42)), length) and near(float(field(vdim, 42)), width), f"{code}: 标注与方案不符"
    x, y = point(hdim, 13, 23)
    assert near_point(point(hdim, 14, 24), (x + length, y))
    assert near_point(point(vdim, 13, 23), (x, y))
    assert near_point(point(vdim, 14, 24), (x, y + width))

    outline = [e for e in items if e["type"] in ("LINE", "ARC") and field(e, 8) == "OUTLINE"]
    top = []
    for entity in outline:
        ends = edge(entity)
        if all(x - EPS <= px <= x + length + EPS and y - EPS <= py <= y + width + EPS for px, py in ends):
            top.append(ends)
    check_closed(top, 2 if code == "P05" else 1, code)

    front_edges = [edge(e) for e in outline if e["type"] == "LINE" and
                   all(p[1] > y + width for p in edge(e))]
    assert any(near(a[0], x) and near(b[0], x) and near(abs(a[1] - b[1]), thickness)
               for a, b in front_edges), f"{code}: 主视图厚度不符"

    if code == "P01":
        assert has_edge(top, (x, y + 10), (x + 10, y))
        assert has_edge(top, (x, y + width - 10), (x + 10, y + width))
        refs = [e for e in items if e["type"] == "CIRCLE" and field(e, 8) == "REFERENCE"]
        assert len(refs) == 1 and near(float(field(refs[0], 40)), 2)
        assert near_point(point(refs[0], 10, 20), (x + 10, y + width / 2))
    if code in ("P05", "P06"):
        cx, cy = x + length / 2, y + width / 2
        arcs = [e for e in outline if e["type"] == "ARC"]
        assert arcs and all(near(float(field(a, 40)), 96) and near_point(point(a, 10, 20), (cx, cy)) for a in arcs)
        for deg in range(0, 360, 45):
            a = radians(deg)
            c, s = cos(a), sin(a)
            p = (cx + 118*c + 7*s, cy + 118*s - 7*c)
            q = (cx + 118*c - 7*s, cy + 118*s + 7*c)
            assert has_edge(top, p, q) == (code == "P05" or deg != 270), f"{code}: {deg}° 销槽不符"
        if code == "P06":
            assert has_edge(top, (cx - 38, y), (x, y))
            assert has_edge(top, (cx + 38, y), (x + length, y))
    counts = Counter(e["type"] for e in items)
    print(f"{code}: {length}×{width}×{thickness} mm，俯视轮廓闭合；{dict(counts)}")


def main():
    directory = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    for code, dimensions in PARTS.items():
        files = list(directory.glob(f"{code}_*.dxf"))
        assert len(files) == 1, f"{code}: 需要且只能有一个 DXF，实际 {len(files)}"
        check(files[0], code, *dimensions)
    print("已检查轮廓、主要尺寸和销槽；安装孔、公差及实物装配仍需验证。")


if __name__ == "__main__":
    main()
