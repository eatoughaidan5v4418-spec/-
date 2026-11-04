/* 验证 v3 网页模拟的状态边界；不验证实际机械、电气或传感器。 */
'use strict';
const assert = require('node:assert/strict');
const { Simulation, GEOM, DOCK, levelZ } = require('../docs/cad/simulation.js');

const close = (a, b) => Math.abs(a - b) < 0.01;

function checkInvariants(sim) {
  const placed = sim.bays.flat().filter(Boolean);
  if (sim.lift.tray) placed.push(sim.lift.tray);
  assert.equal(placed.length, sim.trays.length, '托盘数量在运动中必须守恒');
  assert.equal(new Set(placed.map(t => t.id)).size, sim.trays.length, '托盘不能同时出现在两个位置');
  const { lift } = sim;
  assert(lift.theta >= GEOM.thetaMin - 0.01 && lift.theta <= GEOM.thetaMax + 0.01, '转角超出线缆范围');
  assert(lift.fork >= GEOM.forkPark - 0.01 && lift.fork <= GEOM.forkReach + 0.01, '拨叉超出行程');
  if (sim.motor === '升降电机' || sim.motor === '旋转电机') {
    const engaging = sim.active && /上抬|下降/.test(sim.active.label);
    if (!engaging) assert(close(lift.fork, GEOM.forkPark), '升降或旋转时拨叉必须收回');
  }
  if (lift.tray && close(lift.fork, GEOM.forkPark)) {
    const onLevel = Array.from({ length: sim.layerCount }, (_, l) => levelZ(l));
    if (sim.motor !== '升降电机') assert(onLevel.some(z => close(z, lift.z)) || sim.motor === '旋转电机' || sim.motor === '全部停止', '携盘静止时应在某层啮合高度');
  }
  if (sim.motor === '转运电机') {
    const level = Array.from({ length: sim.layerCount }, (_, l) => l)
      .find(l => close(lift.z, levelZ(l)) || close(lift.z, levelZ(l) - GEOM.free));
    assert(level !== undefined, '拨叉动作只能在某层啮合或脱开高度进行');
    if (lift.tray) assert(close(lift.z, levelZ(level)), '携盘推拉时转运台须与甲板齐平');
  }
}

function runUntil(sim, expected) {
  let steps = 0;
  while (sim.status === 'running' && steps++ < 20000) {
    sim.update(0.05);
    checkInvariants(sim);
  }
  assert.equal(sim.status, expected, sim.label);
}

function snapshot(sim) {
  return sim.trays.map(t => [t.id, t.hasCar]).sort();
}

let cycles = 0;
for (const layers of [1, 2]) {
  for (const autoStage of [true, false]) {
    const sim = new Simulation(layers);
    sim.autoStage = autoStage;
    const capacity = sim.trays.length;
    assert.equal(capacity, 7 * layers, '每层 8 个方位，一层扣 DOCK、二层扣竖井：存车位 = 7N');
    // 先存满。
    while (sim.carCount() < capacity) {
      const before = sim.carCount();
      sim.store();
      runUntil(sim, 'waiting');
      assert(sim.dockTray() && !sim.dockTray().hasCar, 'DOCK 等待放车时应有空托盘');
      assert.equal(sim.carCount(), before, '未确认前车辆状态不得改变');
      sim.update(10);
      assert.equal(sim.status, 'waiting', '等待确认时不得自动继续');
      sim.confirmDock();
      runUntil(sim, 'idle');
      assert.equal(sim.carCount(), before + 1);
      if (autoStage && sim.carCount() < capacity) assert(sim.dockTray(), '存车后应预置空托盘');
      cycles++;
    }
    assert.throws(() => sim.store(), /已满/);
    // 逐一取出每一辆车，再存回。
    for (const tray of sim.trays.slice()) {
      const before = snapshot(sim);
      sim.retrieve(tray.id);
      runUntil(sim, 'waiting');
      assert.equal(sim.dockTray().id, tray.id, '目标托盘应送到 DOCK');
      assert(tray.hasCar, '未确认前车辆仍在托盘上');
      sim.confirmDock();
      runUntil(sim, 'idle');
      assert(!tray.hasCar);
      const after = snapshot(sim);
      assert.deepEqual(after, before.map(([id, car]) => [id, id === tray.id ? false : car]));
      sim.store();
      runUntil(sim, 'waiting');
      sim.confirmDock();
      runUntil(sim, 'idle');
      assert.equal(sim.carCount(), capacity);
      cycles += 2;
    }
    assert.equal(sim.lift.tray, null);
    assert(close(sim.lift.fork, GEOM.forkPark));
  }
}

// 取消存车：空托盘留在 DOCK；下一次存车不需要再动作。
const cancel = new Simulation(2);
cancel.store();
runUntil(cancel, 'waiting');
cancel.cancelDock();
assert.equal(cancel.status, 'idle');
const staged = cancel.dockTray().id;
cancel.store();
cancel.update(0.01);
assert.equal(cancel.status, 'waiting');
assert.equal(cancel.dockTray().id, staged);

// 非法操作与模拟急停。
const stop = new Simulation(2);
assert.throws(() => stop.retrieve('1N'), /载车托盘/);
assert.throws(() => stop.confirmDock(), /没有等待/);
stop.retrieve('2NE');
stop.update(0.3);
stop.stop();
const frozen = JSON.stringify(stop.lift);
stop.update(100);
assert.equal(stop.status, 'stopped');
assert.equal(JSON.stringify(stop.lift), frozen);
assert.throws(() => stop.store(), /正在进行/);
stop.reset(1);
assert.equal(stop.status, 'idle');
assert.equal(stop.trays.length, 7);
assert.throws(() => stop.reset(3), /层数/);
assert.equal(new Simulation(2).bays[1][DOCK.dir], null, '二层 DOCK 正上方为竖井');
assert.equal(DOCK.layer, 0);

console.log(`${cycles} 个存取循环通过：一层样机 / 两层方案、预置开关、存满、逐车取出与存回`);
console.log('托盘守恒、拨叉收回才升降/旋转、齐平推拉、DOCK 确认、取消、急停与重置检查通过');
console.log('测试范围仅为模拟状态；不代表实物安全、碰撞或节拍已经验证。');
