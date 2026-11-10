"""用保守几何包络验证拖链、旋转夹与推拉件的连续相对净空。"""
from __future__ import annotations

import csv
import math
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs'/'cad'/'三维装配_v7_走线优化安装复核'
with (OUT/'装配清单.csv').open(encoding='utf-8-sig',newline='') as f:
    items=list(csv.DictReader(f))
slide=[r for r in items if r['slide']=='True']
assert slide and all(r['lift']=='True' and r['rot']=='True' for r in slide)
jr=[r for r in items if r['id']=='JR_CLAMP' or r['id'].startswith('JR_BOLT_')]
assert len(jr)==5 and all(r['lift']=='True' and r['rot']=='True' and r['slide']=='False' for r in jr)
f=lambda row,key:float(row[key])


def gap(a0,a1,b0,b1):
    return max(0.0,b0-a1,a0-b1)


rows=[]
# 额外扩大 1 mm 的拖链全行程包络：r=111.5..170.5, w=±9.5。
# 固定车位角度下，推拉只改变转运台局部 x，不改变局部 y。
for angle in (-135,-90,-45,0,45,90,135,180):
    delta=math.radians(67.5-angle)
    values=[r*math.sin(delta)+w*math.cos(delta) for r in (111.5,170.5) for w in (-9.5,9.5)]
    lo,hi=min(values),max(values)
    for obj in slide:
        g=gap(lo,hi,f(obj,'y0'),f(obj,'y1'))
        rows.append({'检查':'拖链扩大包络_车位角度_完整推拉','角度':angle,'对象':obj['id'],'保守下界_mm':round(g,4)})

# 缩回状态绕任意角度转动：用物体 AABB 远角作为径向上界。
for obj in slide:
    x=max(abs(f(obj,'x0')),abs(f(obj,'x1')))
    y=max(abs(f(obj,'y0')),abs(f(obj,'y1')))
    g=max(0,111.5-math.hypot(x,y))
    rows.append({'检查':'拖链扩大包络_拨叉缩回_全角度','角度':'连续','对象':obj['id'],'保守下界_mm':round(g,4)})

# JR 本体及头/杆与推拉件一起绕轴旋转、一起升降；在旋转板坐标中比较全推拉 AABB。
jlo={k:min(f(p,k+'0') for p in jr) for k in 'xyz'}
jhi={k:max(f(p,k+'1') for p in jr) for k in 'xyz'}
for obj in slide:
    gaps=[gap(jlo[k],jhi[k],f(obj,k+'0'),f(obj,k+'1')+(138 if k=='x' else 0)) for k in 'xyz']
    g=math.sqrt(sum(v*v for v in gaps))
    rows.append({'检查':'JR总成_相对推拉件_全行程','角度':'连续','对象':obj['id'],'保守下界_mm':round(g,4)})

# Ø3 示例的 JR 端 R12 弯头及竖直出口，用三段 AABB 包络。
# 球探针半径 1.65 足以覆盖 Ø3 线缆及两个采样点之间的弧段。
px,py=63.36313637853419,6.0776739176653685
tx,ty=-0.11359469821118306,0.993527173527886
arc=[(px+12*math.sin(i/64*math.pi/2)*tx,py+12*math.sin(i/64*math.pi/2)*ty,76.5+12*(1-math.cos(i/64*math.pi/2))) for i in range(65)]
def enlarged(points,r):
    return ({k:min(p[i] for p in points)-r for i,k in enumerate('xyz')},
            {k:max(p[i] for p in points)+r for i,k in enumerate('xyz')})
wire_boxes=[enlarged(arc[:46],1.65),enlarged(arc[44:],1.65),({'x':60.5,'y':16.5,'z':87.0},{'x':63.5,'y':19.5,'z':91.0})]
for obj in slide:
    values=[]
    for wire_lo,wire_hi in wire_boxes:
        gaps=[gap(wire_lo[k],wire_hi[k],f(obj,k+'0'),f(obj,k+'1')+(138 if k=='x' else 0)) for k in 'xyz']
        values.append(math.sqrt(sum(v*v for v in gaps)))
    g=min(values)
    rows.append({'检查':'JR示例线缆出口_相对推拉件_全行程','角度':'连续','对象':obj['id'],'保守下界_mm':round(g,4)})

# 平面线环与 JF 入口的 Ø3 包络 z=75..78，推拉件随升降保持相对标高。
for obj in slide:
    g=gap(75,78,f(obj,'z0'),f(obj,'z1'))
    rows.append({'检查':'线环平面_相对推拉件_全行程','角度':'连续','对象':obj['id'],'保守下界_mm':round(g,4)})

with (OUT/'推拉动作_连续几何下界.csv').open('w',encoding='utf-8-sig',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=['检查','角度','对象','保守下界_mm']);writer.writeheader();writer.writerows(rows)
for name in dict.fromkeys(r['检查'] for r in rows):
    minimum=min(r['保守下界_mm'] for r in rows if r['检查']==name)
    print(name, 'min_mm=',minimum)
    assert minimum>0, (name,minimum)
