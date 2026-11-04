/* 立体车库 v3（中央升降塔式）：离线演示用状态机，不连接或控制硬件。
 * 坐标：塔中心为原点，X 右、Y 后、Z 自底板上表面向上，单位 mm。
 * 转运台方向 θ：+u 轴与 +X 的夹角（度），限制在 -135..180（315°），线缆不连续旋转。
 * 计划书方案为两层；样机先做一层（reset(1)）。 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.GarageSimulation = factory();
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  // 8 个辐射车位，按 45° 等分。前侧 S 在一层为 DOCK，在二层为 DOCK 竖井（不设车位）。
  const DIRS = [
    { key: 'E', name: '右', theta: 0 },
    { key: 'NE', name: '右后', theta: 45 },
    { key: 'N', name: '后', theta: 90 },
    { key: 'NW', name: '左后', theta: 135 },
    { key: 'W', name: '左', theta: 180 },
    { key: 'SW', name: '左前', theta: -135 },
    { key: 'S', name: '前', theta: -90 },
    { key: 'SE', name: '右前', theta: -45 }
  ];
  const GEOM = {
    z1: 100,            // 一层甲板上表面
    pitch: 90,          // 层间距
    free: 8,            // 脱开高度：比甲板低 8 mm 时拨叉在销下方
    forkPark: -31,      // 拨叉收回位（携盘时托盘 u = -41..84）
    forkReach: 107,     // 拨叉伸出位（车位内托盘定位销 r = 107）
    trayOffset: 52.5,   // 托盘中心 = 拨叉位置 + 52.5
    trayCenterR: 159.5, // 车位内托盘中心半径
    thetaMin: -135,
    thetaMax: 180
  };
  const DOCK = { layer: 0, dir: 6 };
  const MAX_LAYERS = 2;
  // 实机节拍估算（用于计划书粗估，不是实测）：Z 15 mm/s，转 90° 1.5 s，拨叉 40 mm/s。
  const REAL = { zSpeed: 15, rot90: 1.5, forkSpeed: 40 };

  const close = (a, b) => Math.abs(a - b) < 0.01;
  const requireState = (condition, message) => { if (!condition) throw new Error(message); };
  const levelZ = layer => GEOM.z1 + GEOM.pitch * layer;
  const isDock = (layer, dir) => layer === DOCK.layer && dir === DOCK.dir;
  // DOCK 正上方各层不设车位，保证用户从前方 / 上方放取车的净空。
  const isShaft = (layer, dir) => layer > DOCK.layer && dir === DOCK.dir;
  const isStorage = (layer, dir) => !isDock(layer, dir) && !isShaft(layer, dir);
  const bayName = (layer, dir) => isDock(layer, dir) ? 'DOCK' : `${layer + 1}F-${DIRS[dir].key}`;

  class Simulation {
    constructor(layerCount = 2) { this.reset(layerCount); }

    reset(layerCount = this.layerCount || 2) {
      requireState(layerCount >= 1 && layerCount <= MAX_LAYERS, `层数须为 1..${MAX_LAYERS}。`);
      this.layerCount = layerCount;
      const cars = new Set(['1E', '1NW', '1W', '1SE', '2NE', '2W', '2SW']);
      this.bays = [];
      this.trays = [];
      for (let layer = 0; layer < layerCount; layer++) {
        this.bays.push(DIRS.map((dir, d) => {
          if (!isStorage(layer, d)) return null;
          const tray = { id: `${layer + 1}${dir.key}`, hasCar: cars.has(`${layer + 1}${dir.key}`) };
          this.trays.push(tray);
          return tray;
        }));
      }
      this.lift = { z: levelZ(0) - GEOM.free, theta: 0, fork: GEOM.forkPark, tray: null };
      this.autoStage = true;
      this.status = 'idle';
      this.label = '选择托盘取车，或点击存车';
      this.motor = '全部停止';
      this.active = null;
      this.queue = [];
      this.operation = null;
      this.log = [`演示已就绪：${layerCount} 层，${this.trays.length} 个存车位，DOCK 位于一层前侧。`];
    }

    addLog(message) { this.log.unshift(message); this.log = this.log.slice(0, 8); }
    getTray(id) { return this.trays.find(t => t.id === id); }
    dockTray() { return this.bays[DOCK.layer][DOCK.dir]; }
    carCount() { return this.trays.filter(t => t.hasCar).length; }

    /** 返回托盘所在位置：{ layer, dir } 或 { lift: true }。 */
    locate(id) {
      if (this.lift.tray && this.lift.tray.id === id) return { lift: true };
      for (let layer = 0; layer < this.layerCount; layer++) {
        const dir = this.bays[layer].findIndex(t => t && t.id === id);
        if (dir >= 0) return { layer, dir };
      }
      return null;
    }

    /** 以 DOCK 为起点的简化代价：每层 3 分，每 90° 转动 1 分（转向沿允许区间计算）。 */
    cost(layer, dir) {
      return layer * 3 + Math.abs(DIRS[dir].theta - DIRS[DOCK.dir].theta) / 90;
    }

    nearest(predicate) {
      let best = null;
      for (let layer = 0; layer < this.layerCount; layer++) {
        for (let dir = 0; dir < DIRS.length; dir++) {
          if (!isStorage(layer, dir) || !predicate(this.bays[layer][dir], layer, dir)) continue;
          const c = this.cost(layer, dir);
          if (!best || c < best.cost) best = { layer, dir, cost: c };
        }
      }
      return best;
    }

    forkParked() { return close(this.lift.fork, GEOM.forkPark); }

    enqueue(label, motor, duration, real, start, draw, end) {
      this.queue.push({ label, motor, duration, real, start, draw, end });
    }

    rotateTo(theta) {
      requireState(theta >= GEOM.thetaMin && theta <= GEOM.thetaMax, '转角超出线缆允许范围。');
      let from;
      this.enqueue(`转运台旋转至 θ=${theta}°`, '旋转电机', 0.35, 0,
        action => {
          requireState(this.forkParked(), '拨叉未收回，禁止旋转。');
          from = this.lift.theta;
          const turn = Math.abs(theta - from);
          action.duration = turn < 0.01 ? 0 : 0.3 + turn / 90 * 0.45;
          action.real = turn / 90 * REAL.rot90;
        },
        t => { this.lift.theta = from + (theta - from) * t; });
    }

    liftTo(z, label) {
      let from;
      this.enqueue(label || `升降至 Z=${z} mm`, '升降电机', 0.4, 0,
        action => {
          requireState(this.forkParked(), '拨叉未收回，禁止升降。');
          from = this.lift.z;
          const dz = Math.abs(z - from);
          action.duration = dz < 0.01 ? 0 : 0.35 + dz / GEOM.pitch * 1.0;
          action.real = dz / REAL.zSpeed;
        },
        t => { this.lift.z = from + (z - from) * t; });
    }

    forkTo(target, layer, dir, label) {
      let from;
      this.enqueue(label, '转运电机', 0.9, Math.abs(GEOM.forkReach - GEOM.forkPark) / REAL.forkSpeed,
        () => {
          from = this.lift.fork;
          if (target === GEOM.forkReach) {
            requireState(close(this.lift.theta, DIRS[dir].theta), '转运台未对准目标车位。');
            const bay = this.bays[layer][dir];
            if (this.lift.tray) requireState(close(this.lift.z, levelZ(layer)) && !bay, '携盘伸出须在啮合高度且目标车位为空。');
            else requireState(close(this.lift.z, levelZ(layer) - GEOM.free) && bay, '空叉伸出须在脱开高度且目标车位有托盘。');
          }
        },
        t => { this.lift.fork = from + (target - from) * t; });
    }

    engage(layer, dir) {
      const z = levelZ(layer);
      let from;
      this.enqueue(`升降上抬 ${GEOM.free} mm：拨叉卡入托盘销`, '升降电机', 0.35, GEOM.free / REAL.zSpeed,
        () => {
          requireState(close(this.lift.fork, GEOM.forkReach) && !this.lift.tray && this.bays[layer][dir], '啮合条件不满足。');
          requireState(close(this.lift.z, z - GEOM.free), '啮合前高度不正确。');
          from = this.lift.z;
        },
        t => { this.lift.z = from + (z - from) * t; },
        () => { this.lift.tray = this.bays[layer][dir]; this.bays[layer][dir] = null; });
    }

    release(layer, dir) {
      const z = levelZ(layer);
      let from;
      this.enqueue(`升降下降 ${GEOM.free} mm：拨叉脱离托盘销`, '升降电机', 0.35, GEOM.free / REAL.zSpeed,
        () => {
          requireState(close(this.lift.fork, GEOM.forkReach) && this.lift.tray && !this.bays[layer][dir], '脱开条件不满足。');
          requireState(close(this.lift.z, z), '脱开前高度不正确。');
          this.bays[layer][dir] = this.lift.tray;
          this.lift.tray = null;
          from = this.lift.z;
        },
        t => { this.lift.z = from + (z - GEOM.free - from) * t; });
    }

    /** 从车位取出托盘到转运台。 */
    pick(layer, dir) {
      const name = bayName(layer, dir);
      this.rotateTo(DIRS[dir].theta);
      this.liftTo(levelZ(layer) - GEOM.free, `升降至 ${name} 脱开高度 Z=${levelZ(layer) - GEOM.free}`);
      this.forkTo(GEOM.forkReach, layer, dir, `拨叉伸入 ${name}`);
      this.engage(layer, dir);
      this.forkTo(GEOM.forkPark, layer, dir, `拨叉将托盘拉上转运台`);
    }

    /** 把转运台上的托盘送入车位。 */
    place(layer, dir) {
      const name = bayName(layer, dir);
      this.rotateTo(DIRS[dir].theta);
      this.liftTo(levelZ(layer), `携盘升降至 ${name} 对齐高度 Z=${levelZ(layer)}`);
      this.forkTo(GEOM.forkReach, layer, dir, `拨叉将托盘推入 ${name}`);
      this.release(layer, dir);
      this.forkTo(GEOM.forkPark, layer, dir, '拨叉空载收回');
    }

    moveTray(from, to) { this.pick(from.layer, from.dir); this.place(to.layer, to.dir); }

    finish(message, end) {
      this.enqueue(message, '全部停止', 0, 0, null, null, () => { if (end) end(); });
    }

    begin(kind, id) {
      this.operation = { kind, id, real: 0 };
      this.status = 'running';
    }

    waitDock(kind) {
      this.finish('等待用户在 DOCK 确认', () => {
        this.status = 'waiting';
        this.operation.kind = kind;
        this.addLog(kind === 'store' ? '空托盘已在 DOCK，请放车后确认。' : '车辆已到 DOCK，请取车后确认。');
      });
    }

    complete(message) {
      this.finish(message, () => {
        const real = this.operation ? this.operation.real : 0;
        this.status = 'idle';
        this.operation = null;
        this.addLog(`${message}（实机估算动作时间约 ${Math.round(real)} s）`);
      });
    }

    /** 存车：DOCK 已有空托盘时立即等待放车；否则先取最近的空托盘到 DOCK。 */
    store() {
      requireState(this.status === 'idle', '演示正在进行，无法启动新操作。');
      const dock = this.dockTray();
      requireState(!dock || !dock.hasCar, 'DOCK 上的托盘仍有车。');
      if (!dock) {
        const src = this.nearest(t => t && !t.hasCar);
        requireState(src, '车库已满：没有空托盘。');
        this.begin('store', this.bays[src.layer][src.dir].id);
        this.addLog(`开始存车：调取 ${bayName(src.layer, src.dir)} 的空托盘到 DOCK。`);
        this.moveTray(src, DOCK);
        this.waitDock('store');
      } else {
        this.begin('store', dock.id);
        this.addLog('开始存车：DOCK 已预置空托盘，无需等待。');
        this.waitDock('store');
      }
    }

    /** 取车：DOCK 若有预置空托盘，先送回空位，再调目标托盘到 DOCK。 */
    retrieve(id) {
      requireState(this.status === 'idle', '演示正在进行，无法启动新操作。');
      const tray = this.getTray(id);
      const at = tray && this.locate(id);
      requireState(tray && tray.hasCar && at && !at.lift && !isDock(at.layer, at.dir), '请选择存放在车位中的载车托盘。');
      this.begin('retrieve', id);
      this.addLog(`开始取车：托盘 ${id} 位于 ${bayName(at.layer, at.dir)}。`);
      if (this.dockTray()) {
        const free = this.nearest(t => !t);
        requireState(free, '没有空车位安放 DOCK 上的托盘。');
        this.moveTray(DOCK, free);
      }
      this.moveTray(at, DOCK);
      this.waitDock('retrieve');
    }

    /** 等待放车时用户可取消存车；空托盘留在 DOCK 作为预置。 */
    cancelDock() {
      requireState(this.status === 'waiting' && this.operation.kind === 'store', '只有等待放车时可以取消。');
      this.status = 'idle';
      this.operation = null;
      this.addLog('已取消存车：空托盘留在 DOCK 预置。');
    }

    confirmDock() {
      requireState(this.status === 'waiting' && this.dockTray(), '当前没有等待确认的操作。');
      const tray = this.dockTray();
      const { kind } = this.operation;
      tray.hasCar = kind === 'store';
      this.status = 'running';
      if (kind === 'store') {
        const dest = this.nearest(t => !t);
        requireState(dest, '没有空车位。');
        this.addLog(`用户已放车，托盘 ${tray.id} 送往 ${bayName(dest.layer, dest.dir)}。`);
        this.moveTray(DOCK, dest);
        if (this.autoStage) this.finish('准备预置下一块空托盘', () => {
          const src = this.nearest(t => t && !t.hasCar);
          if (src) {
            this.addLog(`空闲预置：将 ${bayName(src.layer, src.dir)} 空托盘调到 DOCK。`);
            // 插入到"完成"之前执行。
            const done = this.queue.splice(0);
            this.moveTray(src, DOCK);
            this.queue.push(...done);
          }
        });
        this.complete('存车完成');
      } else {
        this.addLog(`用户已取车，托盘 ${tray.id} 已空。`);
        if (!this.autoStage) {
          const dest = this.nearest(t => !t);
          this.moveTray(DOCK, dest);
        }
        this.complete(this.autoStage ? '取车完成，空托盘留在 DOCK 预置' : '取车完成');
      }
    }

    stop() {
      if (this.status === 'idle' || this.status === 'stopped') return;
      this.status = 'stopped';
      this.queue = [];
      this.active = null;
      this.motor = '全部停止';
      this.label = '模拟急停：请重置演示后从已知状态重新开始';
      this.addLog('模拟急停：真实设备须断开电机电源、人工检查托盘与拨叉位置后再恢复。');
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
            if (this.active.start) this.active.start(this.active);
            if (this.operation) this.operation.real += this.active.real || 0;
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
          if (this.status === 'running' && !this.queue.length) this.motor = '全部停止';
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

  return { Simulation, DIRS, GEOM, DOCK, MAX_LAYERS, levelZ, bayName, isDock, isShaft, isStorage };
});
