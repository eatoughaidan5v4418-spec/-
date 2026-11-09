# 星火1号车库 HMI

一层样机的 LVGL 界面，放在官方 `06_demo_lvgl` 例程的 `applications/lvgl` 位置使用。

页面、按键、存取流程和烧录步骤见 [applications/lvgl/demo/README_UI.md](applications/lvgl/demo/README_UI.md)。

本目录只提交应用层：`applications/`、界面端口、`lv_conf.h`，以及从例程摘出来的 `rtconfig.h` 供对照宏。RT-Thread 内核、`packages/LVGL`、`libraries` 和 LCD 驱动仍从星火1号 LVGL 例程拷贝，不在这个仓库里生成。
