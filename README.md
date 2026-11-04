# 华容道式紧凑立体车库调度系统

第十九届重庆市大学生单片机应用设计竞赛 · 方向三  
平台：星火1号 / STM32F407 + RT-Thread 标准版

## 当前硬件方案

当前评审版本为 **硬件方案 v2 / 采购清单 v3**：保留两层 2×2、每层最多 3 辆；采用侧置共用升降台与上方 X/Y 抓取移盘。新的估算外轮廓约 550×300×670 mm。此版本仍须完成结构建模、单层样件和电气/负载验证，不能直接作为最终加工图。

| 文档 | 说明 |
|------|------|
| [docs/硬件方案_v2.md](docs/硬件方案_v2.md) | 布局、抓取、交接、升降、电气和互锁 |
| [docs/采购清单_v3.md](docs/采购清单_v3.md) | 数量、下料长度和带明确假设的预算草案 |
| [docs/硬件验证与实施_v2.md](docs/硬件验证与实施_v2.md) | 已做校核、局限和制作验证顺序 |
| [tools/check_hardware_v2.py](tools/check_hardware_v2.py) | 可重复运行的简化平面布局与预算校核 |

## 历史资料

以下原文和 CAD 示意保留供追溯，属于旧的内置升降井版本，存在已识别的结构和清单冲突，**不得与当前硬件方案混用或直接用于下料**。原比赛计划书也尚未改写为新版方案。

| 文档 | 说明 |
|------|------|
| [docs/计划书.md](docs/计划书.md) | 初赛计划书 |
| [docs/建模参数.md](docs/建模参数.md) | 样机零件级 CAD 参数 |
| [docs/装配清单.md](docs/装配清单.md) | 2×2 样机分步装配（★=等电子） |
| [docs/采购清单.md](docs/采购清单.md) | 冻结实价与淘宝链接 |
| [docs/接口冻结.md](docs/接口冻结.md) | 电气/接口冻结说明 |
| [docs/cad/自制件尺寸与草图.md](docs/cad/自制件尺寸与草图.md) | 自制件尺寸表+草图顺序（A） |
| [docs/cad/p01-baseplate.html](docs/cad/p01-baseplate.html) | P01 底板 · Three.js 精确尺寸查看器 |
| [docs/cad/assembly-exploded.html](docs/cad/assembly-exploded.html) | **整机装配 / 爆炸拆解互动**（Three.js 单页） |

## 历史 CAD 互动页

- [`docs/cad/assembly-exploded.html`](docs/cad/assembly-exploded.html)：旧版 300×180×260 mm 装配示意。
- [`docs/cad/p01-baseplate.html`](docs/cad/p01-baseplate.html)：旧版底板示意。

仓库名 `-` 为创建时占位；后续可在 GitHub 设置里 Rename。
