# 模块化塔式立体车库调度系统

第十九届重庆市大学生单片机应用设计竞赛 · 方向三  
平台：星火1号 / STM32F407 + RT-Thread 标准版

## 当前硬件方案

当前版本为 **硬件方案 v3 / 采购清单 v4**：
- **结构**：中央升降转运台，加上每层 8 个辐射排列、无电机的车位。整机只有 3 个运动轴：升降、旋转、转运拨叉。拨叉与托盘的啮合 / 脱开靠升降上下 8 mm 完成。
- **规模**：计划书按两层、14 个车位写；样机先做一层、7 个车位。
- **外形与预算**：约 520×520×275 mm。一层样机预算约 ¥1,419，两层约 ¥1,614，均含 15% 机动费。

现有 CAD 为 v6 试配方案，仍须完成单件和一层样机验证，不能直接作为最终加工图。

| 文档 | 说明 |
|------|------|
| [docs/计划书.md](docs/计划书.md) | 初赛计划书初稿（按两层 14 车位撰写，含待实测 / 待核标记） |
| [docs/硬件方案_v3.md](docs/硬件方案_v3.md) | 布局、转运机构、升降、层模块、电气、互锁和调度 |
| [docs/采购清单_v4.md](docs/采购清单_v4.md) | 分两批（一层样机 / 第二层扩展包）的数量、下料和预算 |
| [docs/硬件验证与实施_v3.md](docs/硬件验证与实施_v3.md) | 已做校核、未决点和制作验证顺序 |
| [tools/check_hardware_v3.py](tools/check_hardware_v3.py) | 平面几何、高度与预算校核：`py tools/check_hardware_v3.py` |
| [tools/test_cad_simulation.js](tools/test_cad_simulation.js) | 演示状态机测试：`node tools/test_cad_simulation.js` |
| [docs/cad/assembly-exploded.html](docs/cad/assembly-exploded.html) | 三维结构和存取车交互模拟 |
| [docs/cad/layer-plan.html](docs/cad/layer-plan.html) | 层模块俯视和立面尺寸示意 |
| [CAD 索引](docs/cad/README.md) | 当前 v6 三维装配、板件和安装试配详图 |
| [历史版本归档](docs/archive/README.md) | v2 旧方案、v3～v5 CAD 及旧文档备份 |

## CAD 交互演示

用电脑浏览器直接打开 [三维演示](docs/cad/assembly-exploded.html)：
- 点击“存入车辆”，或先选中一个载车托盘再点“取出车辆”。演示过程包括旋转、升降、拨叉啮合与推拉、DOCK 人工确认、空闲预置空托盘、取消存车、暂停和模拟急停。
- 勾选“仅一层样机”，可以切换到一层配置。
- 网址后加 `?view=top` 打开俯视视角，加 `?layers=1` 直接打开一层配置。

页面基于 v3，仅用于演示原理，与 v6 试配方案存在差异；页面不连接实际设备，模型不能作为加工图。Three.js 已放在本地，不依赖网络。

计划书初稿已按 v3 写成，【待实测】项须用一层样机数据替换；机械 CAD 和电气原理图需根据当前方案及一层样机的实测结果继续完善。
