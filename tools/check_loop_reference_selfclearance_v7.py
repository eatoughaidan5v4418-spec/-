"""检查双端 R12 基准示意线的非相邻段距离；不模拟柔性线随转角变形。"""
from __future__ import annotations

import json
import math
from pathlib import Path
import re

root=Path(__file__).resolve().parents[1]
folder=root/'docs'/'cad'/'三维装配_v7_走线优化安装复核'
html=(folder/'走线三维预览_双端R12.html').read_text(encoding='utf-8')
match=re.search(r'const pathCoordinates = (\[[^;]+\]);',html)
if not match:raise ValueError('未找到预览示意线')
flat=json.loads(match.group(1));points=[tuple(flat[i:i+3]) for i in range(0,len(flat),3)]
assert len(points)==311


def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def add(a,b):return tuple(x+y for x,y in zip(a,b))
def mul(a,t):return tuple(x*t for x in a)
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def norm(a):return math.sqrt(dot(a,a))
def endpoint_segment(p,a,b):
    v=sub(b,a);t=max(0.0,min(1.0,dot(sub(p,a),v)/dot(v,v)))
    return norm(sub(p,add(a,mul(v,t))))
def distance(p0,p1,q0,q1):
    u=sub(p1,p0);v=sub(q1,q0);w=sub(p0,q0)
    a=dot(u,u);b=dot(u,v);c=dot(v,v);d=dot(u,w);e=dot(v,w);den=a*c-b*b
    candidates=[endpoint_segment(p0,q0,q1),endpoint_segment(p1,q0,q1),endpoint_segment(q0,p0,p1),endpoint_segment(q1,p0,p1)]
    if abs(den)>1e-12:
        s=(b*e-c*d)/den;t=(a*e-b*d)/den
        if 0<=s<=1 and 0<=t<=1:candidates.append(norm(sub(add(p0,mul(u,s)),add(q0,mul(v,t)))))
    return min(candidates)


lengths=[norm(sub(b,a)) for a,b in zip(points,points[1:])]
cum=[0.0]
for length in lengths:cum.append(cum[-1]+length)
best=(float('inf'),None,None)
for i in range(len(lengths)):
    for j in range(i+2,len(lengths)):
        # 相邻附近按同一条弯曲线束处理；比较至少相隔 9 mm 的非局部段。
        if cum[j]-cum[i+1]<9:continue
        v=distance(points[i],points[i+1],points[j],points[j+1])
        if v<best[0]:best=(v,i,j)
result={'中心线长度_mm':round(cum[-1],3),'非局部段最小中心距_mm':round(best[0],3),'段号':[best[1],best[2]],'非局部定义':'沿线距离至少9 mm；基准多段线，不含柔性变形'}
(folder/'线环示意_自接近检查.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False))
if best[0]<3:raise SystemExit('示意线非相邻段之间的中心距小于 3 mm')
