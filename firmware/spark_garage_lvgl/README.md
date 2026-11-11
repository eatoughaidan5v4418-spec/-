# 车库固件（星火一号 / RT-Thread 标准版）

本工程由 RT-Thread 官方 `STM32F407-RT-SPARK` 资源包的 LVGL 例程（`06_demo_lvgl`）改造而来，芯片为 STM32F407ZGT6。

## 当前进度

| 模块 | 状态 |
|------|------|
| 板载屏调试界面 `applications/lvgl/demo/garage_ui.c` | 已有六个页面（空闲、菜单、存车、取车、进度、故障）；**存取进度是定时器模拟的，没有连接真实运动** |
| 步进驱动（TMC2209 ×3） | 未开始 |
| MCP23017 层检测 | 未开始 |
| 安全监测、运动、调度线程 | 未开始 |
| TJC 串口屏通信 `applications/hmi/` | 后端和协议已写完，接的是假车库 `ui_sim.c`；只在电脑上跑过场景测试，**未接真屏，屏幕工程未做** |

`applications/main.c` 目前是空的；界面由 LVGL 软件包的初始化流程调用 `lv_user_gui_init()` 启动。

## 屏幕策略

- **最终界面是 TJC4827T143 串口屏**，接 USART3（PB10 / PB11），经副转接板连接，外部 5 V 供电。
- **板载 240×240 LCD + LVGL 只是调试界面**，在副转接板和串口屏页面工程完成前用来联调。四个方向键为 PC0（左）、PC1（下）、PC4（右）、PC5（上），用轮询读取，不开外部中断。

后续把界面和业务逻辑分开：调度层只提供车位状态、任务进度和故障码，并接收存车、取车、取消、确认等命令；LVGL 调试屏和串口屏各写一个后端。这样换屏幕时不用改调度和运动代码。

## 引脚

完整分配见 [硬件方案 v4 第 6.3 节](../../docs/硬件方案_v4.md)。

| 功能 | 引脚 |
|------|------|
| 升降 STEP / DIR / EN | PA8（TIM1_CH1）/ PA1 / PD10 |
| 旋转 STEP / DIR / EN | PA0（TIM2_CH1）/ PB14 / PE14 |
| 拨叉 STEP / DIR / EN | PD12（TIM4_CH1）/ PF6 / PF7 |
| 串口屏 | PB10 / PB11（USART3） |
| 层检测 I²C | PB7（SDA）/ PB6（SCL） |
| 检测输入 | PG0～PG7、PD8、PD9 |

EN 低有效。上电后先把三路 EN 置高（禁止），再初始化脉冲输出。PG3、PG6、PD8、PD9 接 5 V 传感器，必须配置为无上下拉的数字输入。

## 编译与下载

- **RT-Thread Studio**：在包管理器里安装 `STM32F407-RT-SPARK` 资源包，导入本工程后编译。
- **MDK**：先双击 `mklinks.bat` 生成 `rt-thread` 和 `libraries` 两个目录链接，再用 Env 生成 MDK5 工程，打开 `project.uvprojx` 编译。

`rt-thread`、`libraries`、`packages`、`build` 都不进仓库。换一台电脑后，需要先装好资源包并重新生成链接，才能编译。

编译完成后，用板载 ST-Link 的 USB 口连接电脑下载。

## 目录

| 路径 | 内容 |
|------|------|
| `applications/main.c` | 入口，目前为空 |
| `applications/lvgl/` | LVGL 显示移植（`lv_port_disp.c`）和配置（`lv_conf.h`） |
| `applications/lvgl/demo/garage_ui.c` | 调试界面 |
| `applications/hmi/` | 串口屏后端、协议、界面与调度的接口，说明见 [串口屏界面方案](../../docs/串口屏界面_v1/README.md) |
| `board/` | 板级初始化、CubeMX 配置、链接脚本 |
| `packages/` | LVGL v8.3.5 等软件包（由包管理器下载） |

## 引用

- RT-Thread 标准版及星火一号 BSP：Apache-2.0
- LVGL：MIT，<https://github.com/lvgl/lvgl>
