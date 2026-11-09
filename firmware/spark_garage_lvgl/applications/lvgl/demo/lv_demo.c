/*
 * Copyright (c) 2006-2021, RT-Thread Development Team
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author        Notes
 * 2021-10-17     Meco Man      first version
 * 2022-05-10     Meco Man      improve rt-thread initialization process
 */
#include <lvgl.h>
#include "garage_ui.h"

void lv_user_gui_init(void)
{
    /* Called by the LVGL thread after the display is ready. Not from main(). */
    garage_ui_init();
}
