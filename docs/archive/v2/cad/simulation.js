/* 立体车库 v2：离线演示用状态机，不连接或控制硬件。 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.GarageSimulation = factory();
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const CELLS = [
    { name: 'A', x: 75, y: 45 }, { name: 'B', x: 225, y: 45 },
    { name: 'C', x: 75, y: 135 }, { name: 'D', x: 225, y: 135 }
  ];
  const ADJACENT = [[1, 2], [0, 3], [0, 3], [1, 2]];
  const HEIGHTS = [200, 420];
  const close = (a, b) => Math.abs(a - b) < 0.01;
  const requireState = (condition, message) => { if (!condition) throw new Error(message); };

  // 以托盘身份搜索，确保移动的是相邻空格；回程按路径倒序复位。
  function routeToD(slots, targetId) {
    const start = slots.map(tray => tray ? tray.id : '');
    const todo = [{ cells: start, moves: [] }];
    const visited = new Set([start.join('|')]);
    for (let i = 0; i < todo.length; i++) {
      const { cells, moves } = todo[i];
      if (cells[3] === targetId) return moves;
      const empty = cells.indexOf('');
      if (empty < 0) break;
      for (const from of ADJACENT[empty]) {
        if (!cells[from]) continue;
        const next = cells.slice();
        const id = next[from];
        next[empty] = id;
        next[from] = '';
        const key = next.join('|');
        if (!visited.has(key)) {
          visited.add(key);
          todo.push({ cells: next, moves: moves.concat({ from, to: empty, id }) });
        }
      }
    }
    throw new Error('当前托盘状态无法规划到交接位。');
  }

  class Simulation {
    constructor() { this.reset(); }

    reset() {
      const make = (level, n, hasCar, cell) => ({
        id: `${level + 1}0${n}`, level, hasCar,
        x: CELLS[cell].x, y: CELLS[cell].y, z: HEIGHTS[level]
      });
      this.layers = [
        [make(0, 1, true, 0), make(0, 2, true, 1), make(0, 3, false, 2), null],
        [make(1, 1, true, 0), make(1, 2, false, 1), make(1, 3, true, 2), null]
      ];
      this.trays = this.layers.flat().filter(Boolean);
      this.heads = HEIGHTS.map(() => ({ x: 225, y: 45, pin: 0 })); // 0 提起，1 插入
      this.liftZ = 70;
      this.platformTray = null;
      this.status = 'idle';
      this.label = '选择一个托盘，开始存车或取车';
      this.motor = '全部停止';
      this.active = null;
      this.queue = [];
      this.operation = null;
      this.log = ['演示已就绪：托盘状态与车辆状态分别记录。'];
    }

    addLog(message) { this.log.unshift(message); this.log = this.log.slice(0, 8); }
    allHeadsClear() { return this.heads.every(h => close(h.pin, 0) && h.x <= 225.01); }
    getTray(id) { return this.trays.find(t => t.id === id); }

    enqueue(label, motor, duration, start, draw, end) {
      this.queue.push({ label, motor, duration, start, draw, end });
    }

    headTo(level, axis, value) {
      const head = this.heads[level];
      let from;
      this.enqueue(`${level + 1} 层抓取头空驶：${axis.toUpperCase()} 轴`, `${level + 1} 层 ${axis.toUpperCase()} 轴`, 0.55,
        () => { requireState(close(head.pin, 0), '抓取销未抬起，不能空驶。'); from = head[axis]; },
        t => { head[axis] = from + (value - from) * t; });
    }

    moveHead(level, x, y) {
      this.headTo(level, 'x', x);
      this.headTo(level, 'y', y);
    }

    pin(level, down) {
      const head = this.heads[level];
      const value = down ? 1 : 0;
      let from;
      this.enqueue(`${level + 1} 层双销${down ? '插入托盘' : '抬起脱离'}`, `${level + 1} 层抓取执行器`, 0.45,
        () => { from = head.pin; }, t => { head.pin = from + (value - from) * t; });
    }

    slide(level, from, to, id) {
      const a = CELLS[from], b = CELLS[to], head = this.heads[level];
      this.moveHead(level, a.x, a.y);
      this.pin(level, true);
      this.enqueue(`${level + 1} 层移盘 ${a.name} → ${b.name} · 托盘 ${id}`, `${level + 1} 层 ${a.x === b.x ? 'Y' : 'X'} 轴`, 0.9,
        () => {
          requireState(ADJACENT[from].includes(to) && this.layers[level][from]?.id === id && !this.layers[level][to], '相邻空位或托盘状态不匹配。');
          requireState(close(head.pin, 1) && close(head.x, a.x) && close(head.y, a.y), '抓取状态与起点不匹配。');
        },
        t => {
          const tray = this.getTray(id);
          tray.x = head.x = a.x + (b.x - a.x) * t;
          tray.y = head.y = a.y + (b.y - a.y) * t;
        },
        () => { this.layers[level][to] = this.layers[level][from]; this.layers[level][from] = null; });
      this.pin(level, false);
    }

    liftTo(z) {
      let from;
      this.enqueue(`升降台移动至 ${z === 70 ? 'DOCK' : z === 200 ? '一层' : '二层'} · Z=${z} mm`, '升降电机', 1.6,
        () => {
          requireState(this.allHeadsClear(), '抓取头未缩回安全区，禁止升降。');
          requireState(!this.platformTray || close(this.platformTray.x, 400), '托盘未完全进入台内，禁止升降。');
          from = this.liftZ;
        },
        t => { this.liftZ = from + (z - from) * t; if (this.platformTray) this.platformTray.z = this.liftZ; });
    }

    roll(toX) {
      let from;
      this.enqueue(toX === 400 ? '滚筒将托盘送入升降台' : '滚筒将托盘送至交接位置', '交接滚筒', 0.9,
        () => {
          requireState(this.platformTray && this.heads.every(h => close(h.pin, 0)), '滚筒启动前须确认托盘存在且双销脱离。');
          from = this.platformTray.x;
          requireState(close(from, toX === 400 ? 300 : 400), '托盘不在预期的交接起点。');
        },
        t => { this.platformTray.x = from + (toX - from) * t; });
    }

    start(kind, level, id) {
      requireState(this.status === 'idle', '演示正在进行，无法启动新操作。');
      const tray = this.layers[level]?.find(t => t && t.id === id);
      requireState(tray && (kind === 'store' || kind === 'retrieve'), '请先选择有效托盘。');
      requireState(kind === 'store' ? !tray.hasCar : tray.hasCar, kind === 'store' ? '请选择空托盘存车。' : '请选择载车托盘取车。');
      const path = routeToD(this.layers[level], id);
      this.operation = { kind, level, id, path };
      this.status = 'running';
      this.addLog(`开始${kind === 'store' ? '存车' : '取车'}：${level + 1} 层托盘 ${id}，规划 ${path.length} 次层内移盘。`);
      this.liftTo(HEIGHTS[level]);
      for (const move of path) this.slide(level, move.from, move.to, move.id);
      const head = this.heads[level];
      this.moveHead(level, 225, 135);
      this.pin(level, true);
      this.enqueue('抓取头将 D 位托盘推至 X=300 交接位', `${level + 1} 层 X 轴`, 0.8,
        () => {
          requireState(this.layers[level][3]?.id === id && !this.platformTray && close(this.liftZ, HEIGHTS[level]), '交接前楼层、平台或托盘状态不匹配。');
          requireState(close(head.pin, 1) && close(head.x, 225) && close(head.y, 135), '抓取头未在交接起点。');
        },
        t => { this.getTray(id).x = head.x = 225 + 75 * t; },
        () => { this.platformTray = this.layers[level][3]; this.layers[level][3] = null; });
      this.pin(level, false);
      this.headTo(level, 'x', 225);
      this.roll(400);
      this.liftTo(70);
      this.enqueue('等待用户在 DOCK 确认放车 / 取车', '全部停止', 0, null, null, () => {
        this.status = 'waiting';
        this.addLog(`升降台已到 DOCK，请确认${kind === 'store' ? '放车' : '取车'}。`);
      });
    }

    confirmDock() {
      requireState(this.status === 'waiting' && this.platformTray, '当前没有等待确认的操作。');
      const { kind, level, id, path } = this.operation;
      this.platformTray.hasCar = kind === 'store';
      this.status = 'running';
      this.addLog(`用户已确认${kind === 'store' ? '放车' : '取车'}，开始送回原层。`);
      this.liftTo(HEIGHTS[level]);
      this.roll(300);
      this.moveHead(level, 300, 135);
      this.pin(level, true);
      const head = this.heads[level];
      this.enqueue('抓取头将托盘拉回 D 位', `${level + 1} 层 X 轴`, 0.8,
        () => {
          requireState(this.platformTray?.id === id && close(this.platformTray.x, 300) && close(head.pin, 1) && close(head.x, 300), '反向交接状态不匹配。');
          requireState(!this.layers[level][3], 'D 位未清空，禁止拉回。');
        },
        t => { this.platformTray.x = head.x = 300 - 75 * t; },
        () => { this.layers[level][3] = this.platformTray; this.platformTray = null; });
      this.pin(level, false);
      for (const move of path.slice().reverse()) this.slide(level, move.to, move.from, move.id);
      this.moveHead(level, 225, 45);
      this.enqueue('存取完成，托盘已复位', '全部停止', 0, null, null, () => {
        this.status = 'idle';
        this.operation = null;
        this.addLog(`${kind === 'store' ? '存车' : '取车'}完成；${level + 1} 层恢复 3 个托盘和 1 个空格。`);
      });
    }

    stop() {
      if (this.status === 'idle' || this.status === 'stopped') return;
      this.status = 'stopped';
      this.queue = [];
      this.active = null;
      this.motor = '全部停止';
      this.label = '模拟急停：请重置演示后从已知状态重新开始';
      this.addLog('模拟急停：真实设备须断电、固定活动件并人工检查后恢复。');
    }

    update(dt) {
      if (this.status !== 'running') return;
      let remaining = Math.max(0, dt);
      try {
        while (this.status === 'running' && (remaining > 0 || !this.active)) {
          if (!this.active) {
            if (!this.queue.length) break;
            this.active = this.queue.shift();
            this.active.elapsed = 0;
            this.label = this.active.label;
            this.motor = this.active.motor;
            if (this.active.start) this.active.start();
          }
          const action = this.active;
          const amount = Math.min(remaining, Math.max(0, action.duration - action.elapsed));
          action.elapsed += amount;
          remaining -= amount;
          const t = action.duration ? Math.min(1, action.elapsed / action.duration) : 1;
          if (action.draw) action.draw(t);
          if (t < 1) break;
          if (action.end) action.end();
          this.active = null;
        }
      } catch (error) {
        this.status = 'stopped';
        this.active = null;
        this.queue = [];
        this.motor = '全部停止';
        this.label = `状态校验失败：${error.message}`;
        this.addLog(this.label);
      }
    }
  }

  return { Simulation, routeToD, CELLS, HEIGHTS };
});
