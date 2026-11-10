"""将 v7 走线试配中的几何关系和待调整处绘成示意图；不是加工图。"""
from __future__ import annotations

import math
from pathlib import Path
import create_wiring_diagrams_v7 as d

ROOT = Path(__file__).resolve().parents[1]
d.OUT = ROOT / 'docs' / 'cad' / '三维装配_v7_走线复核完成'
S = d.SVG
INK, MUTED, TEAL, PURPLE, RED, AMBER = '#17334a', '#5c7182', '#087f8c', '#7254ad', '#cc413b', '#c98719'


def title(s, name, subtitle):
    s.text(65, 78, name, 50, INK, 700)
    s.text(68, 126, subtitle, 24, MUTED)
    s.rect(2000, 40, 325, 58, '#fff0ed', radius=25)
    s.text(2162, 79, '试配未通过 · 禁止按图加工', 22, '#ad4038', 700, 'middle')


def num(s, x, y, value):
    s.circle(x, y, 23, RED, 'white', 3)
    s.text(x, y+8, value, 23, 'white', 700, 'middle')


def poly(s, points, fill, stroke='none', sw=1, extra=''):
    s.add('<polygon points="%s" fill="%s" stroke="%s" stroke-width="%s" %s/>' %
          (' '.join('%.2f,%.2f' % p for p in points), fill, stroke, sw, extra))


def chain_image():
    s = S(); title(s, 'v7 拖链：需要调整的位置', '按当前三维实体试配：67.5° 方位、链体名义 6 × 16、中心线 R25；尺寸单位 mm')
    s.rect(55, 165, 1120, 1370, '#fff', radius=20)
    s.rect(1200, 165, 1145, 1370, '#fff', radius=20)
    s.text(90, 230, '① 径向侧视：两层甲板与拖链', 33, INK, 700)
    s.text(90, 270, '低位实线 / 高位虚线；灰色为甲板，黄色为新增支架', 22, MUTED)
    xr = lambda r: 205+(r-40)*4.65
    yz = lambda z: 1370-z*4.0
    s.line(xr(40), yz(0), xr(215), yz(0), '#8299a7', 10)
    s.text(110, yz(0)+38, '底座 Z=0', 21, MUTED)
    for z, label in [(100, '一层甲板 Z=95～100'), (190, '二层甲板 Z=185～190')]:
        s.rect(xr(160), yz(z), (215-160)*4.65, 20, '#a8b8c3')
        s.text(xr(160)+10, yz(z)-18, label, 20, MUTED, 600)
        s.line(xr(102), yz(z), xr(160), yz(z), '#bacbd4', 2, 'stroke-dasharray="8 7"')
    s.rect(xr(158), yz(4), 16*4.65, 16, '#d8a341', '#a36917', 2)
    s.rect(xr(169), yz(44), 4*4.65, 40*4, '#d8a341', '#a36917', 2)
    s.text(xr(143), yz(35), 'J0  固定座', 22, AMBER, 700)
    s.rect(xr(48), yz(73), (120-48)*4.65, 12, '#e6b955', '#ac7927', 2)
    s.text(xr(48), yz(73)+46, 'J1  随升降支架', 22, AMBER, 700)
    def chain_path(zl):
        m=zl-27; c=(170+zl)/2
        return (f'M {xr(166)} {yz(40)} L {xr(166)} {yz(c)} '
                f'A {25*4.65} {25*4} 0 0 0 {xr(116)} {yz(c)} L {xr(116)} {yz(m)}')
    s.path(chain_path(190), '#c0b0df', 18, extra='stroke-dasharray="14 13"')
    s.path(chain_path(190), PURPLE, 4, extra='stroke-dasharray="14 13"')
    s.path(chain_path(100), '#c6e2e2', 23)
    s.path(chain_path(100), TEAL, 7)
    s.text(265, 405, '高位 ZL=190', 22, PURPLE, 700)
    s.text(265, 447, '低位 ZL=100', 22, TEAL, 700)
    s.circle(xr(166), yz(97.5), 31, 'none', RED, 5)
    num(s, xr(166)+55, yz(97.5)-47, '1')
    s.text(110, 1480, '1  外侧链段穿过一层甲板实体；二层需按全运动包络改口。', 22, RED, 700)
    s.text(1235, 230, '② 俯视：现有槽口与两条链段', 33, INK, 700)
    s.text(1235, 270, '低位截面叠加；浅灰为甲板，白色为现有开口', 22, MUTED)
    cx,cy,scale=1660,1040,2.75
    pt=lambda x,y:(cx+x*scale,cy-y*scale)
    def rw(r,w,a=67.5):
        t=math.radians(a);return pt(r*math.cos(t)-w*math.sin(t),r*math.sin(t)+w*math.cos(t))
    s.add('<defs><clipPath id="p"><rect x="1220" y="300" width="1100" height="1070"/></clipPath></defs><g clip-path="url(#p)">')
    s.rect(1230, 300, 1080, 1060, '#e6edf0')
    s.circle(cx,cy,102*scale,'#fff','#96aab6',3)
    pocket=[(101.76,-7),(125,-7),(125,-13),(160,-13),(160,13),(125,13),(125,7),(101.76,7)]
    poly(s,[rw(r,w) for r,w in pocket],'#fff','#96aab6',3)
    tray=[(100,-20),(110,-30),(225,-30),(225,30),(110,30),(100,20)]
    poly(s,[rw(r,w,45) for r,w in tray],'#c8dce7','#7197aa',3,'fill-opacity="0.60"')
    for r0,r1 in [(113,119),(163,169)]:
        poly(s,[rw(r0,-8),rw(r1,-8),rw(r1,8),rw(r0,8)],TEAL,'#006b78',2)
    for w0,w1 in [(-8,-7),(7,8)]:
        poly(s,[rw(113,w0),rw(119,w0),rw(119,w1),rw(113,w1)],RED)
    s.line(*pt(0,0),*rw(185,0),'#8da0ac',2,'stroke-dasharray="8 7"')
    s.add('</g>')
    x,y=rw(116,0);num(s,x-70,y-70,'2')
    x,y=rw(166,0);num(s,x+56,y-48,'1')
    s.text(1265, 370, '现有井口 R102', 21, MUTED, 600)
    s.text(1265, 405, '现有窄槽：切向宽 14', 21, MUTED, 600)
    s.text(1265, 440, '蓝色：链体截面 6 × 16', 21, TEAL, 700)
    s.text(1265, 475, '浅蓝：45° 车位托盘', 21, '#547e90', 700)
    s.text(1250, 1450, '2  内侧链段比现有 14 mm 窄槽宽；两侧各有名义 1 mm 重叠。', 22, RED, 700)
    s.text(1250, 1485, '支架固定孔、甲板余量及车位支承均需按实物重新设计。', 22, MUTED)
    s.rect(55, 1560, 2290, 112, '#e6eff2', radius=14)
    s.text(85, 1605, '调整方向', 27, INK, 700)
    s.text(235, 1605, '先确定拖链及线材外形 → 重画 P05R / P06R 通道 → 核查相邻托盘与支承 → 再设计 J0 / J1 紧固。', 23, INK)
    s.text(85, 1645, '图示间隙未计安装误差、端头、固定件和电缆弯曲；红圈仅指出位置，不是切割尺寸。', 22, MUTED)
    s.save('01_拖链与支架_调整位置.svg')


def rotary_image():
    s=S();title(s,'v7 旋转线环：需要调整的位置','基准姿态 ZL=100、θ=0 · 黄色环为候选占用区，不代表真实柔性电缆形状')
    s.rect(55,165,1160,1370,'#fff',radius=20);s.rect(1240,165,1105,1370,'#fff',radius=20)
    s.text(90,230,'① 俯视：环形占用区与现有紧固件',33,INK,700)
    s.text(90,270,'局部叠加，遮挡关系为便于识别而简化',22,MUTED)
    cx,cy,sc=640,880,5.0
    pt=lambda x,y:(cx+x*sc,cy-y*sc)
    s.circle(cx,cy,102*sc,'#f8fafb','#a0b2bc',3)
    s.circle(cx,cy,92*sc,'#f9e3b5','#d69b32',3)
    s.circle(cx,cy,59*sc,'#f8fafb','#d69b32',3)
    s.circle(cx,cy,88*sc,'none','#d69b32',2,'stroke-dasharray="9 8"')
    s.circle(cx,cy,62*sc,'none','#d69b32',2,'stroke-dasharray="9 8"')
    outline=[(-90,-39),(-50,-39),(-48,-48),(48,-48),(53,-33),(85,-33),(85,-29),(93,-29),(93,-18),(85,-18),(85,33),(53,33),(48,48),(-48,48),(-53,33),(-90,33)]
    poly(s,[pt(x,y) for x,y in outline],'#9fc0d0','#568194',3,'fill-opacity="0.36"')
    s.circle(cx,cy,31*sc,'#eef3f5','#8fa4b0',3)
    bolts=[(-56,-26.5),(-56,28.5),(56,-26.5),(56,28.5),(-81.85,22),(-75.35,22),(75.35,22),(81.85,22),(-85.5,-12),(-62.5,-35),(87.5,-23.5)]
    for x,y in bolts:
        q=pt(x,y);s.circle(*q,12,RED,'#fff',2)
    for r,w,label,color in [(88,67.5,'JF',TEAL)]:
        a=math.radians(w);x,y=pt(r*math.cos(a),r*math.sin(a));s.circle(x,y,19,'white',color,5);s.text(x+24,y-19,label,24,color,700);num(s,x+78,y-32,'5')
    x,y=pt(58,18);s.rect(x-20,y-20,40,40,'#e0c9ef',PURPLE,4,3);s.text(x+25,y+12,'JR',24,PURPLE,700)
    num(s,*pt(76,35),'3');num(s,*pt(68,12),'4')
    s.text(130, 375,'黄色：R62～88 占用区',22,'#9b6b1c',700)
    s.text(130, 410,'红点：与占用区相交的螺钉 / 螺母',22,RED,700)
    s.text(130, 445,'淡蓝：P03E 转运板',22,'#568194',700)
    s.text(100, 1430,'3  螺钉头、限位座紧固件和惰轮螺母进入线环候选占用区。',22,RED,700)
    s.text(100, 1466,'     这是空间重叠；并不表示已模拟真实线缆轨迹。',21,MUTED)
    s.text(100, 1502,'5  JF 固定夹在 −135° 等姿态碰到转运板；−135° 还碰安装螺钉。',21,RED,700)
    s.text(1275,230,'② 侧向关系：高度与旋转侧线夹',33,INK,700)
    s.text(1275,270,'局部示意，不同部件投影到同一剖面以便阅读',22,MUTED)
    x0,x1=1320,2250
    # 不等比例放大高度，便于识别 3 mm 的相交区域。
    yz=lambda z:1210-(z-70)*36
    s.rect(x0,yz(78),345,5*36,'#b8c8d1','#839ba9',2)
    s.text(x0+32,yz(75)+10,'升降盘',25,INK,700)
    s.rect(1605,yz(79),500,2*36,'#e5c273','#b17b28',2)
    s.text(1630,yz(78)+8,'候选导槽底座',22,INK,700)
    s.rect(1700,yz(85),330,5*36,'#ffe4a8','#d49d36',2)
    s.text(1723,yz(82)+10,'线环占用区',23,'#8e6118',700)
    s.rect(1510,yz(89),680,3*36,'#acc8d6','#5a8597',2)
    s.text(1540,yz(87)+9,'P03E 转运板',23,INK,700)
    s.rect(1990,yz(89),105,7*36,'#d1b3e2',PURPLE,3)
    s.rect(1990,yz(89),105,3*36,'#e65c52',RED,3)
    num(s,2140,yz(88),'4')
    s.rect(1720,yz(86),54,2*36,RED,RED,2)
    num(s,1675,yz(85.5)-20,'3')
    s.line(2195,yz(78),2195,yz(86),MUTED,3,'marker-end="url(#arrow)"')
    s.text(2208,yz(82), '8',25,MUTED,700)
    s.text(1290, 1390,'4  JR 候选线夹与 P03E 实体相交：基准姿态重叠体积 192 mm³。',22,RED,700)
    s.text(1290, 1430,'    需重新设计线夹位置、开孔和护边；导槽高度与紧固件一起调整。',22,MUTED)
    s.text(1290, 1470,'    8 mm 是部件标高差，不是已验证的可用走线净高。',22,MUTED)
    s.rect(55,1560,2290,112,'#e6eff2',radius=14)
    s.text(85,1605,'调整方向',27,INK,700)
    s.text(235,1605,'避开紧固件并重做导槽和线夹，或重新设计转台叠层；最终再用真实线材验证往返收放。',23,INK)
    s.text(85,1645,'线径、可弯半径、盖板、分隔、入口出口及应力释放尚未确定；不得直接按本图加工。',22,MUTED)
    s.save('02_旋转线环_调整位置.svg')


if __name__ == '__main__':
    d.OUT.mkdir(parents=True,exist_ok=True)
    chain_image();rotary_image()
    print('已生成调整位置示意图',d.OUT)
