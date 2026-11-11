"""Generate a photo-estimated YouXin module footprint, KiCad 5 ASCII format."""
from pathlib import Path
import csv
import json
import math
import re
import zipfile
from html import escape

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs' / 'MCP23017_优信模块封装_估算版'
NAME = 'YouXin_MCP23017_21x26_3x10_P2.54_ESTIMATED'
LIB = OUT / 'YouXin_MCP23017.pretty'
LIB.mkdir(parents=True, exist_ok=True)
controls = ['A2', 'A1', 'A0', 'RESET', 'NC_SO', 'NC_CS', 'SDA', 'SCL', 'GND', 'VCC']
b = ['VCC', 'INTB'] + [f'GPB{i}' for i in range(8)]
a = ['GND', 'INTA'] + [f'GPA{i}' for i in range(8)]
# Front/component side: the single control row is on the right.
# Back-photo outer right column is GPA; inner right column is GPB.
pads = []
for start, x, labels in [(1, 9.525, controls), (11, -6.985, b), (21, -9.525, a)]:
    for row, signal in enumerate(labels):
        pads.append(dict(number=start+row, signal=signal, x_mm=x,
                         y_mm=round(-11.43+row*2.54, 4),
                         pad_diameter_mm=1.8, drill_mm=1.0))

lines = [f'(module {NAME} (layer F.Cu) (tedit 0)',
         '  (descr "YouXin MCP23017 module; 21x26 vendor outline; 19.05mm outer span PHOTO ESTIMATE; verify before fabrication")',
         '  (tags "MCP23017 YouXin ESTIMATED 750mil")', '  (attr through_hole)']
def text(kind, value, x, y, layer='F.Fab', size=.8):
    lines.append(f'  (fp_text {kind} "{value}" (at {x} {y}) (layer {layer}) (effects (font (size {size} {size}) (thickness 0.12))))')
def segment(x1, y1, x2, y2, layer, width):
    lines.append(f'  (fp_line (start {x1} {y1}) (end {x2} {y2}) (layer {layer}) (width {width}))')
def rect(x1,y1,x2,y2,layer,width):
    for p,q in [((x1,y1),(x2,y1)),((x2,y1),(x2,y2)),((x2,y2),(x1,y2)),((x1,y2),(x1,y1))]:
        segment(*p,*q,layer,width)
text('reference','REF**',0,-14.7,'F.SilkS',1)
text('value','MCP23017_MODULE',0,14.7,'F.Fab',1)
text('user','ESTIMATED - VERIFY',0,0,'Dwgs.User',1)
text('user','19.05mm OUTER ROW SPAN?',0,2,'Dwgs.User',.8)
rect(-10.5,-13,10.5,13,'F.Fab',.1)
rect(-11.05,-13.55,11.05,13.55,'F.CrtYd',.05)
# Keep silkscreen away from the near-edge pads: top and bottom only.
segment(-10.5,-13,10.5,-13,'F.SilkS',.15)
segment(-10.5,13,10.5,13,'F.SilkS',.15)
segment(8.7,-13,9.525,-12.3,'F.SilkS',.15)
for p in pads:
    n,x,y = p['number'],p['x_mm'],p['y_mm']
    shape = 'rect' if n in (1,11,21) else 'circle'
    lines.append(f'  (pad {n} thru_hole {shape} (at {x} {y}) (size 1.8 1.8) (drill 1) (layers *.Cu *.Mask))')
    tx = 6 if n<=10 else (-4 if n<=20 else -13.1)
    text('user',f'{n}:{p["signal"]}',tx,y,'F.Fab',.65)
lines.append(')')
mod = LIB / f'{NAME}.kicad_mod'
mod.write_text('\n'.join(lines)+'\n',encoding='utf-8')
with (OUT/'引脚坐标与信号.csv').open('w',encoding='utf-8-sig',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(pads[0]));w.writeheader();w.writerows(pads)
(OUT/'尺寸参数.json').write_text(json.dumps(dict(status='PHOTO_ESTIMATE_NOT_MEASURED',
    view='module front/component side, single control row on right',
    body_mm=[21,26],pitch_mm=2.54,outer_span_mm=19.05,double_row_span_mm=2.54,
    remaining_span_mm=16.51,pads=pads),ensure_ascii=False,indent=2),encoding='utf-8')

# An annotated top view, independently readable without an EDA installation.
svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1050" viewBox="-23 -21 46 48">',
     '<rect x="-23" y="-21" width="46" height="48" fill="#10212e"/>',
     '<g font-family="Arial,Microsoft YaHei" fill="white" text-anchor="middle">',
     '<text x="0" y="-18" font-size="1.1">MCP23017 / YouXin / FRONT VIEW</text>',
     '<text x="0" y="-16.2" font-size=".85" fill="#ffcc66">PHOTO ESTIMATE - NOT MEASURED</text>',
     '<rect x="-10.5" y="-13" width="21" height="26" fill="#173c40" stroke="#97c6b0" stroke-width=".13"/>']
for p in pads:
    x,y,n=p['x_mm'],p['y_mm'],p['number']
    if n in (1,11,21):
        svg.append(f'<rect x="{x-.9}" y="{y-.9}" width="1.8" height="1.8" fill="#e9b65a"/>')
    else: svg.append(f'<circle cx="{x}" cy="{y}" r=".9" fill="#e9b65a"/>')
    svg.append(f'<circle cx="{x}" cy="{y}" r=".5" fill="#10212e"/>')
    tx=15.6 if n<=10 else (-2.8 if n<=20 else -16)
    svg.append(f'<text x="{tx}" y="{y+.23}" font-size=".72">{n}: {escape(p["signal"])}</text>')
svg += ['<g fill="#ffcc66" font-size=".9">',
        '<text x="0" y="16">Outer span = 19.05 mm ? / pitch = 2.54 mm ?</text>',
        '<text x="0" y="17.7">Double row = 2.54 mm ? / remaining = 16.51 mm ?</text>',
        '<text x="0" y="19.4">Body = 21 x 26 mm (vendor nominal)</text>',
        '<text x="0" y="21.1">Pad 1.8 / plated drill 1.0 mm (design choice)</text>',
        '<text x="0" y="22.8">Square pads = first pin of each column</text>',
        '</g></g></svg>']
(OUT/'封装预览_正面.svg').write_text('\n'.join(svg),encoding='utf-8')

readme='''# 优信 MCP23017 模块封装（商品图估算版）

本封装用于现成模块插到载板上的三排排母，不是 MCP23017 芯片本体封装。
依据本仓库“使用的硬件资料/商品页已核SKU/MCP23017模块”中的尺寸图和背面丝印图。

## 尺寸与置信度

| 项目 | 采用值 | 依据 |
|---|---|---|
| 模块外形 | 21 × 26 mm | 商品图标称，未实测 |
| 单列针距 | 2.54 mm | 常用排针规格，与照片比例吻合，未实测 |
| 双列中心距 | 2.54 mm | 照片比例估算，未实测 |
| 最外侧列中心距 | 19.05 mm（750 mil） | 照片约 7.4 个针距，取接近的 7.5 个针距，未实测 |
| 控制列到中间列 | 16.51 mm | 由 19.05 − 2.54 得出，未实测 |
| 首末孔中心距 | 22.86 mm | 9 × 2.54，随针距待核对 |
| 圆形镀铜孔 | 1.00 mm | 适配常见 0.64 mm 方针的载板设计值，需核对排母规格 |
| 焊盘 | 1.80 mm | 载板设计值，单侧铜环 0.40 mm |
| 原点 | 模块外形中心 | 设计选择；实际孔阵列边距仍待核对 |

旧 U1 的外侧孔列间距为 20.32 mm（800 mil）；本稿采用 19.05 mm。
两者相差 1.27 mm，不能认定旧库尺寸正确，也不能将本稿称作实测封装。
常用的 2.54 mm 是相邻针距，模块两侧距离没有统一标准。

## 朝向与引脚

从模块正面（芯片面）向下看：最左列 21～30（GND、INTA、GPA0～7）；
中间列 11～20（VCC、INTB、GPB0～7）；最右列 1～10
（A2、A1、A0、RESET、NC/SO、NC/CS、SDA、SCL、GND、VCC）。
每列从上到下编号递增，三列顶部均为方焊盘。背面照片的左右需镜像后才是安装正面。
编号沿用先前 U1 的分组方式；信号依商品背面丝印解释，尚未核对当前原理图符号的逐针映射。
绑定前请按 CSV 对照符号针号，尤其确认 GPA/GPB、VCC/GND 和 INTA/INTB。
每个焊盘独立编号，无预置网络，也没有将相同名称的电源脚或 NC 脚短接。

## 导入嘉立创 EDA 专业版

提供 KiCad 5 ASCII `.kicad_mod` 及 `.pretty` 库压缩包。
官方“格式转换助手”明确支持 `.kicad_mod` 的导入与库提取：
https://prodocs.lceda.cn/cn/import-export/easyeda-pro-format-converter/

1. 在格式转换助手选择 KiCad，将源目录指向解压后的 `.pretty` 文件夹，选择一个新的输出目录。
2. 扫描并转换该封装库文件。
3. 在嘉立创 EDA 专业版使用“文件 → 导入 → 嘉立创EDA（专业版）”导入转换结果。
4. 打开封装，复核 30 个孔、三列位置、方焊盘和针号，再绑定器件。

当前 MCP 无封装几何编辑/库导入接口，因此本次交付文件，没有替换工程 U1。
本地检查验证了语法结构、孔数、编号、坐标、间距和铜环；尚未在嘉立创转换器中实际转换或运行原生封装规则检查。
建议按 100% 比例打印或用实物排母试配；验证外侧孔距后再用于制板。
'''
(OUT/'说明与导入步骤.md').write_text(readme,encoding='utf-8')

# Validate the serialized artifact, not just the in-memory geometry.
raw=mod.read_text(encoding='utf-8')
tokens=re.findall(r'"(?:\\.|[^"\\])*"|[()]|[^\s()]+',raw)
def parse(i=0):
    assert tokens[i]=='('
    node=[];i+=1
    while tokens[i]!=')':
        if tokens[i]=='(': child,i=parse(i);node.append(child)
        else: node.append(tokens[i]);i+=1
    return node,i+1
tree,end=parse();assert end==len(tokens) and tree[0]=='module'
ps=[v for v in tree if isinstance(v,list) and v[0]=='pad']
assert len(ps)==30 and {int(p[1]) for p in ps}==set(range(1,31))
def field(p,key):return next(v[1:] for v in p if isinstance(v,list) and v[0]==key)
xy=[tuple(map(float,field(p,'at'))) for p in ps]
assert len(set(xy))==30
assert abs(min(math.dist(p,q) for i,p in enumerate(xy) for q in xy[i+1:])-2.54)<1e-6
assert all(field(p,'drill')==['1'] and field(p,'size')==['1.8','1.8'] for p in ps)
report={'pads':30,'unique_numbers':True,'minimum_center_spacing_mm':2.54,
        'minimum_copper_gap_mm':.74,'annular_ring_mm':.4,
        'outer_span_mm':19.05,'syntax':'balanced and parsed KiCad S-expression',
        'native_EDA_import_verified':False,'physical_dimensions_verified':False}
(OUT/'验证结果.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
with zipfile.ZipFile(OUT/'YouXin_MCP23017_封装库.zip','w',zipfile.ZIP_DEFLATED) as z:
    z.write(mod,mod.relative_to(OUT))
with zipfile.ZipFile(OUT/'YouXin_MCP23017_封装库.zip','r') as z:
    assert z.testzip() is None
print(json.dumps({'output':str(OUT),'verification':report},ensure_ascii=False))
