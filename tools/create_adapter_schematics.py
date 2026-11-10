"""Build unwired EasyEDA Standard schematic pages from the accepted two-board pin tables."""
from __future__ import annotations

import json
import math
import re
import uuid
import zipfile
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / 'docs' / '转接板_双板_v2'
OUT = ROOT / 'docs' / '嘉立创原理图_双板_v1'
FONT = 'C:/Windows/Fonts/msyh.ttc'
BOLD = 'C:/Windows/Fonts/msyhbd.ttc'


def uid() -> str:
    return 'gge' + uuid.uuid4().hex[:16]


def clean(s: str) -> str:
    if any(t in s for t in ['~', '^', '#@$', '`', '\n']):
        raise ValueError(f'Unsupported delimiter in text: {s!r}')
    return s


class Sheet:
    def __init__(self, title: str, width: int, height: int):
        self.title, self.width, self.height = title, width, height
        self.shapes: list[str] = []
        self.components: list[dict] = []
        self.draw_ops: list[tuple] = []
        self.section_boxes: list[tuple] = []

    def text(self, text, x, y, size=11, color='#334155', bold=False, into=None, typ='L', visible=1):
        text = clean(str(text))
        # The two optional fields after font size are font weight and italic.
        s = '~'.join(map(str, ['T', typ, x, y, 0, color, 'Microsoft YaHei', f'{size}pt',
                              'bold' if bold else '', '', '', 'comment', text, visible,
                              'start', uid(), 0, '']))
        (self.shapes if into is None else into).append(s)
        if visible:
            self.draw_ops.append(('text', text, x, y, size, color, bold))

    def rect(self, x, y, w, h, color='#94a3b8', fill='none', into=None, stroke=1):
        s = '~'.join(map(str, ['R', x, y, '', '', w, h, color, stroke, 0, fill, uid(), 0, '']))
        (self.shapes if into is None else into).append(s)
        self.draw_ops.append(('rect', x, y, w, h, color, fill, stroke))

    def line(self, points, color='#880000', into=None, stroke=1):
        s = '~'.join(map(str, ['PL', ' '.join(map(str, points)), color, stroke, 0, 'none', uid(), 0]))
        (self.shapes if into is None else into).append(s)
        self.draw_ops.append(('line', points, color, stroke))

    def section(self, x, y, w, h, title, subtitle=''):
        self.rect(x, y, w, h, '#A8B4C4', stroke=1)
        self.text(title, x + 14, y + 25, 14, '#155E75', True)
        if subtitle:
            self.text(subtitle, x + 14, y + 47, 9, '#64748B')
        self.section_boxes.append((x, y, w, h, title))

    def pin(self, x, y, num, label, length, into, show_name=True, show_num=True):
        # All pin coordinates are local schematic geometry, not inferred package-pad coordinates.
        end = x + length
        anchor = 'start' if length > 0 else 'end'
        name_x = end + (7 if length > 0 else -7)
        num_x = end - (8 if length > 0 else -8)
        rot = 180 if length > 0 else 0
        label = clean(label)
        s = (f'P~show~0~{num}~{x}~{y}~{rot}~{uid()}~0'
             f'^^{x}~{y}^^M {x} {y} h {length}~#880000'
             f'^^{int(show_name)}~{name_x}~{y+4}~0~{label}~{anchor}~~8pt~#000080'
             f'^^{int(show_num)}~{num_x}~{y-4}~0~{num}~{anchor}~~7pt~#880000'
             f'^^0~{end}~{y}^^0~')
        into.append(s)
        self.draw_ops.append(('line', [x, y, end, y], '#880000', 1))
        self.draw_ops.append(('pin_dot', x, y))
        if show_name:
            self.draw_ops.append(('pin_text', label, name_x, y + 4, 8, '#000080', anchor))
        if show_num:
            self.draw_ops.append(('pin_text', str(num), num_x, y - 4, 7, '#880000', anchor))

    def component(self, ref, value, x, y, parts, pins, kind, **properties):
        if any(c['ref'] == ref for c in self.components):
            raise ValueError(f'Duplicate reference {ref}')
        self.text(ref, x, y - 30, 10, '#000080', into=parts, typ='P')
        self.text(value, x, y - 12, 9, '#000080', into=parts, typ='N')
        attrs = {'package': '', 'nameAlias': 'Value', 'Value': value,
                 'Manufacturer Part': '', 'Supplier Part': '', 'Supplier': '',
                 'spicePre': 'X' if kind == 'connector' else kind[:1].upper(),
                 'spiceSymbolName': value, 'Contributor': 'Project custom schematic symbol'}
        props = '`'.join(clean(str(t)) for kv in attrs.items() for t in kv)
        symbol_uuid, device_uuid = uuid.uuid4().hex, uuid.uuid4().hex
        header = '~'.join(map(str, ['LIB', x, y, props, 0, 0, uid(), symbol_uuid,
                                   device_uuid, 0, '', 'yes', 'yes', '', 0, '']))
        self.shapes.append(header + '#@$' + '#@$'.join(parts))
        self.components.append({'ref': ref, 'value': value, 'kind': kind,
                                'pins': pins, 'x': x, 'y': y,
                                'footprint': None, **properties})

    def connector(self, ref, value, x, y, nets, scheme='single', width=190, pitch=20, **props):
        parts = []
        n = len(nets)
        rows = n if scheme == 'single' else math.ceil(n / 2)
        h = (rows - 1) * pitch + 30
        self.rect(x, y, width, h, '#880000', into=parts)
        pins = []
        for index, name in enumerate(nets):
            num = index + 1
            if scheme == 'single':
                side, row = 0, index
            elif scheme == 'odd_even':
                side, row = index % 2, index // 2
            elif scheme == 'pmod':
                side, row = index // rows, index % rows
            else:
                raise ValueError(scheme)
            px = x - 25 if side == 0 else x + width + 25
            py = y + 15 + row * pitch
            self.pin(px, py, num, name, 25 if side == 0 else -25, parts)
            pins.append({'number': str(num), 'name': name, 'x': px, 'y': py})
        self.component(ref, value, x, y, parts, pins, 'connector',
                       numbering=scheme, symbol_box=[x, y, width, h], **props)

    def passive(self, ref, value, x, y, kind='resistor', note=''):
        parts = []
        if kind == 'resistor':
            self.rect(x - 15, y - 6, 30, 12, '#880000', into=parts)
            self.pin(x - 30, y, '1', '1', 15, parts, False, False)
            self.pin(x + 30, y, '2', '2', -15, parts, False, False)
        elif kind == 'capacitor':
            self.line([x - 5, y - 12, x - 5, y + 12], into=parts)
            self.line([x + 5, y - 12, x + 5, y + 12], into=parts)
            self.pin(x - 30, y, '1', '1', 25, parts, False, False)
            self.pin(x + 30, y, '2', '2', -25, parts, False, False)
        else:
            raise ValueError(kind)
        pins = [{'number': str(i), 'name': str(i), 'x': px, 'y': y}
                for i, px in [(1, x - 30), (2, x + 30)]]
        self.component(ref, value, x - 40, y, parts, pins, kind, note=note)
        if note:
            self.text(note, x - 45, y + 25, 8, '#64748B')

    def json(self):
        return {'head': {'docType': '1', 'editorVersion': '6.5.51', 'newgId': True,
                         'c_para': {'Prefix Start': '1'}, 'c_spiceCmd': 'null',
                         'hasIdFlag': True, 'uuid': uuid.uuid4().hex,
                         'x': '0', 'y': '0', 'importFlag': 0, 'transformList': ''},
                'canvas': f'CA~{self.width}~{self.height}~#FFFFFF~yes~#DDDDDD~5~{self.width}~{self.height}~line~5~pixel~5~0~0',
                'shape': self.shapes,
                'BBox': {'x': 0, 'y': 0, 'width': self.width, 'height': self.height},
                'colors': {}}

    def render(self, path):
        scale = 1.5
        im = Image.new('RGB', (round(self.width * scale), round(self.height * scale)), 'white')
        draw = ImageDraw.Draw(im)
        fonts = {}

        def f(size, bold=False):
            key = (size, bold)
            if key not in fonts:
                fonts[key] = ImageFont.truetype(BOLD if bold else FONT, round(size * 4/3 * scale))
            return fonts[key]

        for op in self.draw_ops:
            if op[0] == 'rect':
                _, x, y, w, h, col, fill, sw = op
                draw.rectangle([x*scale, y*scale, (x+w)*scale, (y+h)*scale],
                               outline=col, fill=None if fill == 'none' else fill,
                               width=max(1, round(sw*scale)))
            elif op[0] == 'line':
                _, pts, col, sw = op
                draw.line([(pts[i]*scale, pts[i+1]*scale) for i in range(0, len(pts), 2)],
                          fill=col, width=max(1, round(sw*scale)))
            elif op[0] == 'text':
                _, txt, x, y, size, col, bold = op
                draw.text((x*scale, y*scale), txt, font=f(size, bold), fill=col, anchor='ls')
            elif op[0] == 'pin_text':
                _, txt, x, y, size, col, anc = op
                draw.text((x*scale, y*scale), txt, font=f(size), fill=col,
                          anchor='ls' if anc == 'start' else 'rs')
            elif op[0] == 'pin_dot':
                _, x, y = op
                rr = 1.5*scale
                draw.ellipse([x*scale-rr, y*scale-rr, x*scale+rr, y*scale+rr], fill='#9CA3AF')
        im.save(path)


def read_tables(filename):
    text = (DOC / filename).read_text(encoding='utf-8')
    raw = {}
    for m in re.finditer(r'^\| (\d+) \| ((?:P2|CN5|CN6)\.\d+) \| ([^|]+) \|', text, re.M):
        source = m.group(2).split('.')[0]
        raw.setdefault(source, {})[int(m.group(1))] = m.group(3).strip()
    spare_text = text.split('## 4.')[1].split('## 5.')[0]
    spare = {int(m.group(1)): m.group(2).strip()
             for m in re.finditer(r'^\| (\d+) \| ([^|]+) \|', spare_text, re.M)}
    ports = []
    split = re.split(r'### (J_[MS]\d+)：([^，\n]+)，XH(\d+)P\n', text)
    for i in range(1, len(split), 4):
        ref, label, number, body = split[i:i+4]
        body = body.split('\n## ')[0]
        pins = [(int(m.group(1)), m.group(2).strip())
                for m in re.finditer(r'^\| (\d+) \| ([^|]+) \|', body, re.M)]
        assert [x[0] for x in pins] == list(range(1, int(number)+1)), ref
        ports.append({'ref': ref, 'label': label, 'nets': [x[1] for x in pins]})
    return raw, [spare[i] for i in range(1, 17)], ports


def title(sh, subtitle):
    sh.text('星火一号 · ' + sh.title, 45, 48, 24, '#0F172A', True)
    sh.text(subtitle, 47, 83, 12, '#475569')
    sh.text('待连线原理图：元件已放置；引脚名称只是标注，没有导线、网络标签或隐式电源连接。',
            47, 111, 12, '#B45309', True)


def driver_card(sh, port, x, y, gpio):
    sh.section(x, y, 510, 355, port['label'], 'STEP / DIR / EN 独立控制；5P不是电机相线口')
    sh.connector(port['ref'], 'XH-5P / 2.54mm', x+35, y+95, port['nets'], width=185,
                 connector_family='XH-compatible', pitch_mm=2.54, role='driver_control')
    pre = port['ref'].split('_')[1]
    axis = {'J_M101': 'Z', 'J_M102': 'T', 'J_S103': 'U'}[port['ref']]
    for k, (suffix, value) in enumerate([('STEP', '47R'), ('DIR', '47R'), ('EN', '0R'), ('ENPU', '10k')]):
        sh.passive(f'R_{pre}_{axis}_{suffix}', value, x+385, y+100+k*60)
    sh.passive(f'C_{pre}_{axis}_VIO', '100nF', x+130, y+295, 'capacitor')
    sh.text(gpio, x+22, y+335, 10, '#475569')


def main_sheet(raw, spare, ports):
    sh = Sheet('主转接板 / 40Pin直插', 2440, 1920)
    title(sh, '按双板v2逐针表绘制 · 主板15个XH接口 · 未用信号转2×8排针 · 2026-11-07')
    sh.section(45, 155, 520, 615, '星火 P2 输入', '2×20公排针焊底面；原理图按星火P2编号')
    sh.connector('J_M001', 'HEADER_2x20 / 2.54mm', 145, 255,
                 [raw['P2'][i] for i in range(1, 41)], 'odd_even', 320, 22,
                 role='spark_P2_input', mount='bottom')
    sh.text('14/30脚单独保留CFG网络，不能在本板强制接地。', 65, 744, 10, '#B45309')
    sh.section(45, 810, 520, 345, '未用GPIO与电源排针', 'H_M001 · 2×8公排针 · 所有16针均已标注')
    sh.connector('H_M001', 'HEADER_2x8 / 2.54mm', 145, 915, spare, 'odd_even', 320, 22,
                 role='spare_header')
    byref = {p['ref']: p for p in ports}
    driver_card(sh, byref['J_M101'], 610, 155, 'STEP=PA8 / DIR=PA1 / EN=PD10')
    driver_card(sh, byref['J_M102'], 1150, 155, 'STEP=PA0 / DIR=PB14 / EN=PE14')
    sh.section(1690, 155, 705, 355, '层板 I²C接口', '两个4P口并联；SDA=PB7，SCL=PB6')
    for k, ref in enumerate(['J_M120', 'J_M121']):
        sh.connector(ref, 'XH-4P / 2.54mm', 1730+k*340, 250, byref[ref]['nets'], width=210,
                     connector_family='XH-compatible', pitch_mm=2.54, role='layer_i2c')
    for j, (ref, val) in enumerate([('R_M_SDA', '0R'), ('R_M_SCL', '0R'),
                                   ('R_M_SDA_PU', '4.7k DNP'), ('R_M_SCL_PU', '4.7k DNP')]):
        sh.passive(ref, val, 1790+(j%2)*310, 395+(j//2)*65)
    sh.text('I²C上拉按全总线核算；默认不装。', 1710, 491, 9, '#64748B')
    gpio = {'J_M130': 'PG0 / EXTI0', 'J_M131': 'PG1 / EXTI1', 'J_M132': 'PG2 / EXTI2',
            'J_M140': 'PG3 / EXTI3', 'J_M150': 'PG4 / EXTI4', 'J_M151': 'PG5 / EXTI5',
            'J_M141': 'PG6 / EXTI6', 'J_M133': 'PG7 / EXTI7',
            'J_M142': 'PD8 / EXTI8', 'J_M143': 'PD9 / EXTI9'}
    refs = ['J_M130', 'J_M131', 'J_M132', 'J_M140', 'J_M150', 'J_M151',
            'J_M141', 'J_M133', 'J_M142', 'J_M143']
    for idx, ref in enumerate(refs):
        p = byref[ref]
        x, y = 610+(idx%3)*600, 560+(idx//3)*285
        sh.section(x, y, 585, 255, p['label'], gpio[ref] + '；输入电平按3.3V兼容设计')
        sh.connector(ref, f'XH-{len(p["nets"])}P / 2.54mm', x+35, y+100, p['nets'], width=210,
                     connector_family='XH-compatible', pitch_mm=2.54, role='detector')
        suffix = ref[3:]
        sh.passive(f'R_{suffix}_SER', '1k', x+355, y+105)
        pu = '10k' if len(p['nets']) == 2 else '10k OPT'
        sh.passive(f'R_{suffix}_PU', pu, x+490, y+105)
        sh.passive(f'C_{suffix}_FLT', '10nF DNP', x+355, y+190, 'capacitor')
        if len(p['nets']) == 3:
            sh.passive(f'C_{suffix}_VCC', '100nF', x+490, y+190, 'capacitor')
        sh.text('EXT → 串阻 → MCU；上拉/滤波放MCU侧。', x+18, y+238, 9, '#64748B')
    p = byref['J_M160']
    sh.section(1210, 1415, 585, 255, '转台检测组合口', '与J_M141 / J_M150 / J_M151共用信号，按线束选装')
    sh.connector('J_M160', 'XH-6P / 2.54mm', 1245, 1520, p['nets'], width=225,
                 connector_family='XH-compatible', pitch_mm=2.54, role='combined_detector')
    sh.text('同一信号只放一套输入滤波。', 1510, 1540, 10, '#64748B')
    sh.text('6脚NC：备用，不接电源或地。', 1510, 1570, 10, '#64748B')
    sh.section(45, 1200, 520, 470, '主板逻辑电源', 'V3P3_OUT来自P2.1/17；不得与副板V3_S短接')
    sh.passive('R_M_PWR', '0R / 测流断点', 220, 1320)
    sh.passive('C_M_PWR_100N', '100nF', 220, 1430, 'capacitor')
    sh.passive('C_M_PWR_10U', '10uF', 420, 1430, 'capacitor')
    sh.passive('C_M_LAYER1', '100nF', 220, 1540, 'capacitor')
    sh.passive('C_M_LAYER2', '100nF', 420, 1540, 'capacitor')
    sh.text('V3P3_OUT → R_M_PWR → V3_M', 80, 1610, 11, '#334155')
    sh.text('P2的5V仅保留到H_M001，不给屏幕供电。', 80, 1642, 10, '#64748B')
    sh.section(45, 1710, 2350, 165, '连线提示', '所有端点保留给你手动连线；这里只提供元件、真实引脚号和功能标注。')
    sh.text('三路电机相线与12V配电仍在独立TMC底座；本图XH5P是VIO/GND/STEP/DIR/EN控制接口。', 65, 1785, 11)
    sh.text('P2只接主板；PMOD只接副板。输入EXT端与MCU端之间经过串阻，避免同名网标把串阻旁路。', 65, 1815, 11)
    sh.text('封装未绑定，PCB、布线与生产文件由你后续处理；屏幕/传感器现有线序仍需逐针核对。', 65, 1845, 11, '#64748B')
    return sh


def side_sheet(raw, spare, ports):
    sh = Sheet('副转接板 / PMOD侧插', 1860, 1450)
    title(sh, '按双板v2逐针表绘制 · 两组PMOD弯针 · 2个XH接口 · 未用信号转2×8排针 · 2026-11-07')
    sh.section(45, 155, 520, 690, '侧边 PMOD 输入', '弯公排针：一列1-6，另一列7-12，不能套奇偶编号')
    for j, (ref, source_name) in enumerate([('J_S001', 'CN5'), ('J_S002', 'CN6')]):
        sh.connector(ref, 'PMOD1 / 2x6 / RA' if j == 0 else 'PMOD2 / 2x6 / RA',
                     145, 250+j*305, [raw[source_name][i] for i in range(1, 13)],
                     'pmod', 320, 25, role=source_name+'_input', mount='right_angle')
    sh.section(45, 900, 520, 355, '未用 PMOD 信号排针', 'H_S001 · 2×8公排针；15/16脚NC')
    sh.connector('H_S001', 'HEADER_2x8 / 2.54mm', 145, 1010, spare, 'odd_even', 320, 22,
                 role='spare_header')
    byref = {p['ref']: p for p in ports}
    driver_card(sh, byref['J_S103'], 610, 155, 'STEP=PD12 / DIR=PF6 / EN=PF7')
    sh.section(1180, 155, 635, 710, '串口屏 XH接口与串口直连选项', '用户确认接头间距2.54mm；屏TX/RX以设备方向标注')
    sh.connector('J_S110', 'XH-4P / 2.54mm', 1220, 255, byref['J_S110']['nets'], width=250,
                 connector_family='XH-compatible', pitch_mm=2.54, role='hmi')
    sh.passive('R_S_TX', '0R DNP', 1620, 290)
    sh.passive('R_S_RX', '0R DNP', 1620, 390)
    sh.text('MCU_PB10 → R_S_TX → 屏RX', 1210, 430, 10)
    sh.text('屏TX → R_S_RX → MCU_PB11', 1210, 460, 10)
    sh.text('确认TTL电平兼容后才装直连0R；否则加电平转换。', 1210, 495, 10, '#B45309')
    sh.passive('JP_HMI5', '0R DNP / 5V', 1340, 590)
    sh.passive('JP_HMI3', '0R DNP / 3V3', 1650, 590)
    sh.text('V5_EXT_S → JP_HMI5 → VHMI_S', 1210, 650, 10)
    sh.text('V3_S → JP_HMI3 → VHMI_S', 1210, 680, 10)
    sh.text('两路选一，默认均不装；按屏完整型号定电源。', 1210, 715, 10, '#B45309')
    sh.passive('C_S_HMI_100N', '100nF', 1340, 790, 'capacitor')
    sh.passive('C_S_HMI_BULK', '10uF OPT', 1650, 790, 'capacitor')
    sh.section(610, 565, 510, 690, '副板电源入口', 'PMOD仅有3.3V；屏幕外部5V从螺丝端子进入')
    sh.connector('J_S200', 'TERMINAL_2P / 屏外部5V', 650, 665, ['V5_EXT_S', 'GND'], width=260,
                 role='external_5v_terminal')
    sh.passive('R_S_PWR', '0R / 测流断点', 800, 840)
    sh.passive('C_S_PWR_100N', '100nF', 740, 960, 'capacitor')
    sh.passive('C_S_PWR_10U', '10uF', 1000, 960, 'capacitor')
    sh.text('V3P3_CORE → R_S_PWR → V3_S', 635, 1040, 11)
    sh.text('V3_S供拨叉VIO和EN上拉；不与主板V3_M短接。', 635, 1080, 10, '#B45309')
    sh.text('外部5V不接PMOD的3.3V，也不反向给星火供电。', 635, 1120, 10, '#B45309')
    sh.text('地线共参考；电机大电流不经过副板。', 635, 1160, 10, '#64748B')
    sh.section(1180, 920, 635, 335, '连接器与装配说明', '这里只画原理图元件，封装选择与PCB由你后续处理')
    sh.text('拨叉DIR=PF6、EN=PF7；不再从主板跨接两根线。', 1205, 1000, 11)
    sh.text('小电机线端2.0mm，在TMC输出侧配套，不是J_S103。', 1205, 1040, 11)
    sh.text('大电机线端与屏幕2.54mm，现有线序按设备丝印核对。', 1205, 1080, 11)
    sh.text('PMOD1未用引脚全到H_S001；不把重复接口当新GPIO。', 1205, 1120, 11)
    sh.text('两组弯针的间距、朝向和支撑孔按星火实物量取。', 1205, 1160, 11, '#64748B')
    sh.text('本页没有导线或网络标签。屏电源桥及串口直连0R默认不装，留待实物规格确认。',
            55, 1340, 13, '#B45309', True)
    sh.text('原理图符号未绑定封装；本次不包含PCB、布线、Gerber或下单。', 55, 1385, 12, '#64748B')
    return sh


def main():
    OUT.mkdir(exist_ok=True)
    mr, ms, mp = read_tables('01_主板逐针接线.md')
    sr, ss, sp = read_tables('02_副板逐针接线.md')
    assert len(mp) == 15 and sum(len(p['nets']) for p in mp) == 48
    assert len(sp) == 2 and sum(len(p['nets']) for p in sp) == 9
    sheets = [main_sheet(mr, ms, mp), side_sheet(sr, ss, sp)]
    project = {'editorVersion': '6.5.51', 'docType': '5',
               'title': '星火一号双板转接_原理图待连线',
               'description': '仅原理图元件与引脚标注；用户自行连接导线。无PCB及封装绑定。',
               'colors': {}, 'schematics': []}
    manifests = []
    for index, sh in enumerate(sheets, 1):
        data = sh.json()
        # No wire/netlabel/netflag/junction primitive is permitted in this deliverable.
        assert not any(x.split('~', 1)[0] in {'W', 'N', 'F', 'J', 'B', 'BE', 'O'} for x in sh.shapes)
        for c in sh.components:
            assert len({p['number'] for p in c['pins']}) == len(c['pins'])
        doc = {'docType': '1', 'title': '主板_40Pin直插' if index == 1 else '副板_PMOD弯针',
               'description': '待手动连线。引脚名仅作说明。', 'dataStr': data}
        project['schematics'].append(doc)
        prefix = '01_主板_待连线' if index == 1 else '02_副板_待连线'
        (OUT / (prefix + '.json')).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
        sh.render(OUT / (prefix + '.png'))
        manifests.append({'sheet': doc['title'], 'components': sh.components,
                          'component_count': len(sh.components),
                          'connector_count': sum(c['kind'] == 'connector' for c in sh.components),
                          'wire_count': 0, 'net_label_count': 0, 'pcb_count': 0})
    full = OUT / '星火一号双板转接_原理图待连线.json'
    full.write_text(json.dumps(project, ensure_ascii=False, indent=2), encoding='utf-8')
    (OUT / '原理图对象与引脚核对.json').write_text(json.dumps(manifests, ensure_ascii=False, indent=2), encoding='utf-8')
    with zipfile.ZipFile(OUT / '星火一号双板转接_原理图待连线.zip', 'w', zipfile.ZIP_DEFLATED) as z:
        z.write(full, full.name)
    report = {'format': 'EasyEDA Standard JSON, importable via EasyEDA Pro standard-edition import',
              'source': 'accepted two-board v2 pin tables',
              'sheets': [{k: v for k, v in m.items() if k != 'components'} for m in manifests],
              'footprints_assigned': False, 'app_import_verified': False}
    (OUT / '检查结果.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
