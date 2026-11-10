"""绘制 v7 走线优化后的甲板通道、支架和旋转导槽示意图。"""
from __future__ import annotations

import math
from pathlib import Path
import create_wiring_diagrams_v7 as d

ROOT=Path(__file__).resolve().parents[1]
d.OUT=ROOT/'docs'/'cad'/'三维装配_v7_走线优化安装复核'
S=d.SVG
INK,MUTED,BLUE,GOLD,PURPLE,RED='#17334a','#5b7181','#087f8c','#c48820','#a45dc0','#c94c43'


def header(s,title,sub):
    s.text(65,78,title,49,INK,700);s.text(68,125,sub,24,MUTED)
    s.rect(2030,40,295,56,'#fff3d7',radius=24)
    s.text(2177,77,'几何试配 · 非加工图',22,'#8a5b12',700,'middle')


def local_panel(s,x0,y0,new):
    s.rect(x0,y0,1080,1030,'#fff',radius=20)
    s.text(x0+35,y0+65,'调整后 · 甲板通道' if new else '调整前 · 甲板通道',33,INK,700)
    s.text(x0+35,y0+105,'67.5° 径向局部俯视；白色为开口，灰色为甲板',21,MUTED)
    bx=x0+105;cy=y0+545;scale=9.0
    X=lambda r:bx+(r-92)*scale
    Y=lambda w:cy-w*scale
    s.rect(X(92),Y(30),88*scale,60*scale,'#e4ebee')
    # 真实井口边界 r=sqrt(102²-w²)；只绘局部范围。
    boundary=[(X(math.sqrt(102**2-w*w)),Y(w)) for w in range(-30,31)]
    points=[(X(92),Y(-30))]+boundary+[(X(92),Y(30))]
    d.polygon(points)
    s.add(f'<polygon points="{d.polygon(points)}" fill="white"/>')
    if new:
        s.rect(X(100),Y(13),74*scale,26*scale,'white','#91a8b4',3)
    else:
        s.rect(X(100),Y(7),25*scale,14*scale,'white','#91a8b4',3)
        s.rect(X(125),Y(13),35*scale,26*scale,'white','#91a8b4',3)
    s.line(X(102),Y(-30),X(102),Y(30),'#a8b9c2',2,'stroke-dasharray="8 7"')
    s.text(X(102)+8,Y(30)-17,'R102 井口',19,MUTED,600)
    s.rect(X(113),Y(8),6*scale,16*scale,'#19a1ad',BLUE,3)
    s.rect(X(163),Y(8),6*scale,16*scale,'#19a1ad',BLUE,3)
    if new:
        s.rect(X(111),Y(10),10*scale,20*scale,'none',GOLD,4,0,'stroke-dasharray="10 7"')
        s.text(X(110),Y(20),'J1 端头包络',21,GOLD,700)
        s.line(X(169.14),Y(-18),X(174),Y(-18),BLUE,3,'marker-start="url(#arrow)" marker-end="url(#arrow)"')
        s.text(X(171.57),Y(-22),'外侧约 4.9',20,BLUE,700,'middle')
        s.line(X(149),Y(13),X(149),Y(-13),BLUE,3,'marker-start="url(#arrow)" marker-end="url(#arrow)"')
        s.text(X(150)+15,Y(0),'26',22,BLUE,700)
        s.text(x0+38,y0+905,'内侧按支架外宽 20 预留，槽口每侧名义余量约 3。',23,BLUE,700)
        s.text(x0+38,y0+943,'外侧链体名义厚 6；转弯分段外伸计入约 4.9。',21,MUTED)
    else:
        s.circle(X(166),Y(0),48,'none',RED,4)
        s.circle(X(116),Y(0),55,'none',RED,4)
        s.text(x0+38,y0+905,'原窄槽宽 14，小于链体外宽 16；外侧链段超出 r160。',23,RED,700)
        s.text(x0+38,y0+943,'两处均发生实体相交。',21,MUTED)
    s.text(X(113),Y(-29),'内侧 r113～119',19,BLUE,700)
    s.text(X(159),Y(-29),'外侧 r163～169',19,BLUE,700)
    for r in (100,125,160,174):
        s.line(X(r),Y(-32),X(r),Y(-34),MUTED,2);s.text(X(r),Y(-37),str(r),19,MUTED,400,'middle')
    s.text(x0+765,y0+890,'r 向外 →',22,MUTED,700)


def deck_image():
    s=S();header(s,'v7 甲板通道与拖链支架：调整前后','模型坐标：67.5° 方位，r 为径向、w 为切向；单位 mm')
    local_panel(s,55,165,False);local_panel(s,1265,165,True)
    s.rect(55,1220,2290,370,'#fff',radius=20)
    s.text(90,1290,'支架与配套孔',33,INK,700)
    s.text(95,1343,'J0 底座：一体式固定座 + 端头容纳腔；底板同步增加 2 个 Ø3.4 试配孔。',24,INK)
    s.text(95,1387,'J1 升降侧：支架与旋转线环导槽一体；升降盘同步增加 2 个 Ø2.2 试配孔。',24,INK)
    s.text(95,1431,'拖链端头在容纳腔内留 0.5 名义余量；紧固件仅按候选外包络建模。',23,MUTED)
    s.text(95,1490,'已对模型中 13 个停放托盘的甲板支承投影复算：修改前后面积相同；不代表强度已通过。',23,BLUE,700)
    s.text(95,1530,'修改后通道为 r100～174、切向 ±13；实际开口须按所选拖链和端头复核。',22,MUTED)
    s.text(95,1565,'车位之间误推拉会撞拖链，运动条件和互锁见图 3。',21,RED,700)
    s.rect(55,1610,2290,70,'#e6eff2',radius=12)
    s.text(85,1655,'说明：本图按候选链体 6 × 16、R25 绘制；未计实物误差、变形与线束选型。',22,INK)
    s.save('01_甲板通道与支架_优化对照.svg')


def rotary_image():
    s=S();header(s,'v7 旋转线环导槽与线夹：优化试配','基准 ZL=100；为便于比较，将不同方位部件投影到同一径向剖面')
    s.rect(55,165,1250,1370,'#fff',radius=20);s.rect(1330,165,1015,1370,'#fff',radius=20)
    s.text(90,230,'① 高度与连接关系',34,INK,700)
    s.text(90,270,'黄色：固定侧 / 绿色：旋转侧 / 紫色：线环占用区',21,MUTED)
    xr=lambda r:185+(r-45)*16
    yz=lambda z:1240-(z-69)*34
    # 升降盘和一体支架（高度按基准实际标高）。
    s.rect(xr(45),yz(78),(58-45)*16,5*34,'#b8c8d1','#839ba9',2)
    s.text(xr(45)+20,yz(75)+8,'升降盘',21,INK,700)
    s.rect(xr(48),yz(73),(102-48)*16,3*34,'#e6b95f','#b77f28',2)
    s.text(xr(48)+120,yz(71)+8,'J1 一体支架',23,INK,700)
    s.rect(xr(59),yz(74),(92-59)*16,1*34,'#e5b251','#b77f28',2)
    s.rect(xr(59),yz(79),2*16,5*34,'#e5b251','#b77f28',2)
    s.rect(xr(91),yz(79),1*16,5*34,'#e5b251','#b77f28',2)
    s.rect(xr(62),yz(78.5),(90-62)*16,4*34,'#e6d1ee','#a45dc0',3,0,'fill-opacity="0.55"')
    s.text(xr(72),yz(76.2),'线环占用区',23,'#8a469e',700)
    # 不同方位的板、夹投影。
    s.rect(xr(55),yz(89),(99-55)*16,3*34,'#accbd8','#638e9d',2)
    s.text(xr(75),yz(87)+8,'P03E 转运板',23,INK,700)
    s.rect(xr(56.1),yz(86),(73.4-56.1)*16,6*34,'#90c6b7','#448e7b',3)
    s.text(xr(67.2),yz(83)+8,'JR',23,'#255f55',700)
    s.rect(xr(93),yz(79),6*16,6*34,'#e2ab44','#b77f28',3)
    s.rect(xr(93),yz(78.5),6*16,4*34,'#fff','#b77f28',2)
    s.text(xr(93),yz(80)+5,'JF',22,GOLD,700)
    s.rect(xr(62.3),yz(89),4.5*16,9*34,'#fff','#6f8794',2)
    s.text(xr(62.3),yz(90)+15,'Ø4.5',20,MUTED,700)
    s.rect(xr(49.25),yz(80.5),5.5*16,2.5*34,'#6d8090','#526a79',2)
    s.text(xr(45),yz(82)+5,'原支撑臂螺钉头',20,MUTED,700)
    s.path(f'M {xr(98)} {yz(76.5)} L {xr(79)} {yz(76.5)} L {xr(65)} {yz(76.5)} L {xr(64.6)} {yz(80.5)}',PURPLE,5,extra='stroke-dasharray="9 7"')
    s.text(115,1425,'紫色虚线仅示意连接关系；双端 R12 轨迹和线夹入口槽请看三维模型。',21,PURPLE,700)
    s.text(1370,230,'② 新的固定与穿线方式',34,INK,700)
    def item(y,n,title,lines):
        s.circle(1390,y-8,24,BLUE,'none');s.text(1390,y,n,22,'white',700,'middle')
        s.text(1435,y,title,28,INK,700)
        for j,line in enumerate(lines):s.text(1435,y+39+j*34,line,22,MUTED)
    item(340,'1','JF 固定侧线夹',['中心约 r96；预留 5 × 4 穿线通道。','2 个 Ø2.2 试配孔与 J1 支架对齐。'])
    item(510,'2','JR 旋转侧线夹',['移至板下 Z80～86；入口加切向避让槽。','转运板 x62、y18 开 Ø4.5 候选穿线孔。'])
    item(680,'3','一体导槽',['J1 支架与环形底座、内外壁合为一体。','在 67.5° 外壁开口，接入 JF。'])
    item(850,'4','候选紧固件',['J0、J1、JF、JR 各按两颗候选紧固件建包络。','实际螺钉、螺纹、螺母及装配方式待选定。'])
    s.rect(1370,1010,890,240,'#f4eef8','#dfcde9',2,14)
    s.text(1400,1055,'仍需验证',26,INK,700)
    s.text(1400,1100,'线环占用区仅高 4 mm，Ø4.5 孔和 5 × 4 口',22,INK)
    s.text(1400,1137,'是否容纳 10 芯柔性线束，取决于实际线材。',22,INK)
    s.text(1400,1174,'基准弯头中心线 R12，Ø3 线缆内侧约 R10.5；',22,MUTED)
    s.text(1400,1211,'须按线材规格的半径定义核对，并验证往返。',22,MUTED)
    s.text(1380,1360,'连续包络通过仅适用于本次建模的刚性候选件。',22,BLUE,700)
    s.text(1380,1400,'未建模的线束、插头和末端引出仍需检查。',22,MUTED)
    s.text(1380,1440,'JR 入口槽上方局部厚度仅 0.8，强度需试做。',22,RED,700)
    s.rect(55,1560,2290,120,'#e6eff2',radius=14)
    s.text(85,1608,'复核结果',27,INK,700)
    s.text(245,1608,'227 个预设姿态无新增实体相交；非车位 67.5° 误推拉会撞拖链，必须落实互锁。',23,RED,700)
    s.text(85,1650,'夹座安装面和端头容纳腔不适用连续包络的 1 mm；全装配与真实软线仍需验证。',21,MUTED)
    s.save('02_旋转导槽与线夹_优化方案.svg')


def interlock_image():
    s=S();header(s,'v7 运动复核：拖链与推拉互锁','基准 ZL=100、推拉行程 U=138 的俯视；仅画拖链和移动托盘，其他零件省略')
    def panel(x0,theta,problem):
        s.rect(x0,165,1095,1260,'#fff',radius=20)
        s.text(x0+35,230,'非车位角度误推拉：发生相交' if problem else '对准车位后推拉：拖链避开托盘',31,RED if problem else BLUE,700)
        s.text(x0+35,270,'θ=67.5°，U=138' if problem else 'θ=45°，U=138',22,MUTED)
        cx,cy,sc=x0+425,1050,3.2
        pt=lambda x,y:(cx+x*sc,cy-y*sc)
        def local(r,w,a):
            a=math.radians(a);return pt(r*math.cos(a)-w*math.sin(a),r*math.sin(a)+w*math.cos(a))
        s.circle(cx,cy,102*sc,'#f5f9fa','#acbec7',3)
        s.text(cx-84,cy+10,'井口 R102',21,MUTED,700)
        tray=[(100,-20),(110,-30),(225,-30),(225,30),(110,30),(100,20)]
        s.add(f'<polygon points="{d.polygon([local(r,w,theta) for r,w in tray])}" fill="#9cc8d6" fill-opacity="0.58" stroke="#4b8aa1" stroke-width="4"/>')
        for r0,r1 in ((113,119),(163,169)):
            p=[local(r0,-8,67.5),local(r1,-8,67.5),local(r1,8,67.5),local(r0,8,67.5)]
            s.add(f'<polygon points="{d.polygon(p)}" fill="{RED if problem else BLUE}" stroke="white" stroke-width="3"/>')
        x,y=local(116,0,67.5)
        s.text(x+35,y-20,'拖链内侧段',21,RED if problem else BLUE,700)
        x,y=local(166,0,67.5)
        s.text(x+35,y-20,'拖链外侧段',21,RED if problem else BLUE,700)
        s.text(x0+45,1320,'移动托盘未碰到拖链。' if not problem else '移动托盘与两段拖链均发生相交。',23,RED if problem else BLUE,700)
        if problem:s.text(x0+45,1360,'Z=100、θ=67.5°：U=34.5 即检测到相交。',21,RED,700)
    panel(55,45,False);panel(1250,67.5,True)
    s.rect(55,1460,2290,220,'#fff2ee','#edd0c9',2,14)
    s.text(90,1510,'动作条件必须落实',29,RED,700)
    s.text(90,1555,'旋转前确认拨叉已收回；推拉前确认转盘已停止并对准有效车位。',24,INK)
    s.text(90,1595,'项目网页仅为演示，实际控制和检测须实现并验证互锁；啮合 / 脱开按机构工序受控执行。',22,MUTED)
    s.text(90,1637,'正常车位角度的推拉与收回状态下的旋转已做保守连续净空计算；其他组合不能视为安全。',21,MUTED)
    s.save('03_运动互锁与拖链_风险示意.svg')


if __name__=='__main__':
    d.OUT.mkdir(parents=True,exist_ok=True)
    deck_image();rotary_image();interlock_image()
    print('已生成三张优化与运动风险示意图。')
