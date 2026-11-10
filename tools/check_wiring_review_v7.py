"""检查交付的 v7 走线模型清单、姿态记录及代表性相交结果的一致性。"""
from __future__ import annotations

import csv
import json
import math
from pathlib import Path

root = Path(__file__).resolve().parents[1]
folder = root / 'docs' / 'cad' / '三维装配_v7_走线复核完成'


def read(name):
    with (folder/name).open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


manifest = read('装配清单.csv')
coverage = read('姿态_覆盖.csv')
hits = read('姿态_实体相交.csv')
swept = read('全行程_保守包络候选.csv')
stats = json.loads((folder/'检查统计.json').read_text(encoding='utf-8-sig'))
assert len(manifest) == 340 == len({r['id'] for r in manifest})
assert len([r for r in manifest if r['layer']=='W_CHAIN']) == 20
assert len(coverage) == stats['姿态数'] == 225
assert len(hits) == stats['相交记录'] == 7269
assert len(swept) == stats['包络候选'] == 1006
assert stats['错误'] == 0 and not read('检查错误.csv')
assert len({(r['Z'],r['角度'],r['行程']) for r in coverage}) == 192

# 每一条采样相交记录都应落在全行程保守候选内。
pair_set = {(r['新增件'],r['对象']) for r in swept}
for r in hits:
    key = ('CHAIN_ALL' if r['新增件'].startswith('CHAIN_') else r['新增件'],r['对象'])
    assert key in pair_set, ('采样记录未落入全行程候选',key)

byid = {r['id']:r for r in manifest}
a = math.radians(67.5)
for name,radius in [('J0_FOOT',166),('J0_STAND',171),('J0_CLAMP',166),('J1_ARM',84),('J1_CLAMP',116),('JF_CLAMP',88),('CHAIN_0',166),('CHAIN_1',116)]:
    r = byid[name];x=(float(r['x0'])+float(r['x1']))/2;y=(float(r['y0'])+float(r['y1']))/2
    assert abs(x*math.cos(a)+y*math.sin(a)-radius)<.001, name
    assert abs(-x*math.sin(a)+y*math.cos(a))<.001, name

baseline={(r['新增件'],r['对象']):float(r['体积']) for r in hits if r['阶段']=='基准'}
for pair,vol in [(('CHAIN_0','DECK_L1'),480),(('CHAIN_1','DECK_L1'),60),(('JR_CLAMP','TRANSFER_PLATE'),192)]:
    assert abs(baseline[pair]-vol)<.001, pair
assert {'-135','-90','45','90'} == {r['角度'] for r in hits if r['新增件']=='JF_CLAMP' and r['对象']=='TRANSFER_PLATE'}
assert {r['Z'] for r in hits if r['对象']=='DECK_L2'} >= {'160','182','190','194'}
for name in ['车库_v7_走线候选_含示意线.dwg','车库_v7_走线候选.SAT','走线三维预览.html','走线三维预览.png','01_拖链与支架_调整位置.png','02_旋转线环_调整位置.png','验证_重开.txt']:
    assert (folder/name).stat().st_size > 100, name
print('复核通过：340 个装配实体、225 条姿态、192 个不同组合、1006 对保守候选；代表性相交和标注一致。')
