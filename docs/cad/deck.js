/* 甲板井孔轮廓（v3）：三维演示与尺寸图共用。坐标 X 右、Y 后，单位 mm。
 * 井孔 = R96 圆 + 8 个定位销槽（±7，至 r118）+ 4 个支撑臂槽（±7，至 r125）与竖向件口袋（±13，r125…160）。
 * 二层甲板另在前侧开 ±38 DOCK 竖井缺口，与井孔连通。 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.GarageDeck = factory();
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  const R = 96, HALF = 7, SHAFT_HALF = 38, EDGE = 250;
  const BAYS = [0, 45, 90, 135, 180, 225, 270, 315];
  const MEMBERS = [22.5, 67.5, 112.5, 202.5];   // 导杆 22.5 / 202.5，丝杆 112.5，拖链 67.5
  const deg = Math.PI / 180;
  const local = (a, u, w) => [u * Math.cos(a * deg) - w * Math.sin(a * deg), u * Math.sin(a * deg) + w * Math.cos(a * deg)];
  const c0 = Math.sqrt(R * R - HALF * HALF);
  const SHAPES = {
    slot: [[c0, -HALF], [118, -HALF], [118, HALF], [c0, HALF]],
    pocket: [[c0, -HALF], [125, -HALF], [125, -13], [160, -13], [160, 13], [125, 13], [125, HALF], [c0, HALF]]
  };
  const FEATURES = BAYS.map(a => ({ a, kind: 'slot' })).concat(MEMBERS.map(a => ({ a, kind: 'pocket' })));
  const halfAngle = Math.asin(HALF / R) / deg;

  /** 沿角度递增方向，从 a0 到 a1 的井孔边界点（含途经的槽口）。 */
  function arc(a0, a1) {
    const points = [];
    const pushArc = (from, to) => {
      for (let t = from; t < to; t += 2) points.push([R * Math.cos(t * deg), R * Math.sin(t * deg)]);
      points.push([R * Math.cos(to * deg), R * Math.sin(to * deg)]);
    };
    const list = FEATURES.map(f => {
      let x = f.a;
      while (x < a0) x += 360;
      while (x >= a0 + 360) x -= 360;
      return Object.assign({ x }, f);
    })
      .filter(f => f.x - halfAngle > a0 && f.x + halfAngle < a1).sort((p, q) => p.x - q.x);
    let current = a0;
    for (const f of list) {
      pushArc(current, f.x - halfAngle);
      for (const [u, w] of SHAPES[f.kind]) points.push(local(f.a, u, w));
      current = f.x + halfAngle;
    }
    pushArc(current, a1);
    return points;
  }

  /** 一层甲板：外框方形，井孔为独立闭合孔。 */
  const hole = () => arc(-11.25, 348.75);

  /** 二层甲板：外轮廓含前侧竖井缺口，无独立井孔。 */
  function shaftOutline() {
    const phi = Math.acos(SHAFT_HALF / R) / deg;
    return [[SHAFT_HALF, -EDGE], [EDGE, -EDGE], [EDGE, EDGE], [-EDGE, EDGE], [-EDGE, -EDGE], [-SHAFT_HALF, -EDGE]]
      .concat(arc(-phi, 180 + phi).reverse());
  }

  return { R, EDGE, SHAFT_HALF, BAYS, MEMBERS, hole, shaftOutline };
});
