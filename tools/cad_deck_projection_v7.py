"""从 v7 甲板俯视 DXF 推导正视图和侧视图投影。"""
import json
from pathlib import Path
import sys

from cad_deck_projection_v3 import get_profile, projection


def main():
    if len(sys.argv) != 2:
        raise SystemExit("用法：py tools/cad_deck_projection_v7.py 甲板图纸目录")
    source = Path(sys.argv[1])
    result = {}
    for code in ("P05", "P06"):
        paths = list(source.glob(f"{code}*.dxf"))
        if len(paths) != 1:
            raise ValueError(f"{code}: 预期一个 DXF，实际 {len(paths)}")
        length, width, segments = get_profile(paths[0])
        front_visible, front_hidden = projection(length, width, segments, 0)
        left_visible, left_hidden = projection(length, width, segments, 1)
        result[code] = {"front_visible": front_visible, "front_hidden": front_hidden,
                        "left_visible": left_visible, "left_hidden": left_hidden}
    print(json.dumps(result, ensure_ascii=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
