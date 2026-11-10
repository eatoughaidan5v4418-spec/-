"""核对 v7 走线优化交付件、检查数据和已知运动边界。"""
from __future__ import annotations

import csv
import json
from pathlib import Path
import re
import struct

root=Path(__file__).resolve().parents[1]
folder=root/'docs'/'cad'/'三维装配_v7_走线优化安装复核'


def read(name):
    with (folder/name).open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))


manifest=read('装配清单.csv');coverage=read('姿态_覆盖.csv')
stats=json.loads((folder/'检查统计.json').read_text(encoding='utf-8-sig'))
assert len(manifest)==350==len({r['id'] for r in manifest})
assert len([r for r in manifest if r['layer']=='W_CHAIN'])==20
assert len([r for r in manifest if r['layer']=='W_FASTENER'])==16
assert len(coverage)==stats['姿态数']==227
assert len({(r['Z'],r['角度'],r['行程']) for r in coverage})==194
assert all(int(r['相交记录'])==0 for r in coverage)
assert not read('姿态_实体相交.csv') and not read('检查错误.csv')
assert stats['错误']==0 and stats['相交记录']==0
sweep=read('关键零件_连续包络实体检查.csv')
assert len(sweep)==stats['连续实体检查']==670
assert all(abs(float(r['相交体积_mm3']))<1e-9 for r in sweep)
assert len(read('全行程_保守包络候选.csv'))==stats['包络候选']==1682
support=read('甲板_托盘支承投影.csv')
assert len(support)==13 and all(abs(float(r['减少_mm2']))<1e-8 for r in support)
audit=read('缓存结果_独立复算.csv')
assert len(audit)==2 and all(r['结论']=='逐对体积一致' and int(r['相交数'])==0 for r in audit)

continuous=read('推拉动作_连续几何下界.csv')
expected={'拖链扩大包络_车位角度_完整推拉':3.8923,'拖链扩大包络_拨叉缩回_全角度':19.4728,'JR总成_相对推拉件_全行程':3.5,'JR示例线缆出口_相对推拉件_全行程':4.7453,'线环平面_相对推拉件_全行程':11.5}
for name,value in expected.items():
    group=[float(r['保守下界_mm']) for r in continuous if r['检查']==name]
    assert group and abs(min(group)-value)<.0002,(name,group)

off=read('非车位角度_推拉相交.csv')
assert any(r['角度']=='67.5' and r['行程']=='34.5' and r['对象']=='CENTER_TRAY' for r in off)
assert len(off)==11
wire=read('线环Ø3_双端R12_空间探针覆盖.csv')
assert len(wire)==138 and all(int(r['相交数'])==0 for r in wire)
assert not read('线环Ø3_双端R12_空间探针相交.csv')
ref=json.loads((folder/'线环示意_自接近检查.json').read_text(encoding='utf-8'))
assert ref['非局部段最小中心距_mm']>3
relief=read('双端R12线夹入口_移除体积.csv')
assert len(relief)==1 and 90<float(relief[0]['移除体积_mm3'])<100

for name in ['车库_v7_走线优化_双端R12.dwg','车库_v7_走线优化_双端R12.SAT','走线三维预览_双端R12.html','验证_双端R12重开.txt']:
    assert (folder/name).stat().st_size>100,name
for name in ['01_甲板通道与支架_优化对照.png','02_旋转导槽与线夹_优化方案.png','03_运动互锁与拖链_风险示意.png','走线三维预览_双端R12.png']:
    data=(folder/name).read_bytes()[:24]
    assert data[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',data[16:24])[0]>=1800,name

report=(folder/'README.md').read_text(encoding='utf-8')
for link in re.findall(r'\]\(((?:\./|\.\./)[^)]+)\)',report):
    assert (folder/link).exists(),link
print('优化交付核对通过：350 个装配实体，227 条预设姿态，670 条连续包络检查，非车位碰撞与 3 mm 双端 R12 示例均有记录。')
