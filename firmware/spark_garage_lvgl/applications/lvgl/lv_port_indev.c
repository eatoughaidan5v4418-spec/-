/*
 * Copyright (c) 2006-2022, RT-Thread Development Team
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2021-10-18     Meco Man     The first version
 */
#include <lvgl.h>
#include <stdbool.h>
#include <rtdevice.h>
#include <board.h>

/*
 * The spark board used here has no touch panel. Keys are active-low GPIOs
 * polled from garage_ui.c (PC0 left, PC1 down, PC4 right, PC5 up).
 * Leave this input device empty so LVGL does not wait on a touch controller.
 */
void lv_port_indev_init(void)
{

}
