/*
 * ui_sim.c - stand-in for the garage core, so the serial screen can run
 * before motion control and scheduling exist. Timing is fake; nothing moves.
 *
 * msh: sim_fault <code>   raise a fault (e.g. sim_fault 12)
 *      sim_estop <0|1>    press / release the emergency stop
 */
#include <rtthread.h>
#include <rthw.h>
#include <stdlib.h>
#include "ui_model.h"
#include "hmi_tjc.h"

#ifdef HMI_USING_SIM

#define STEP_MS     2000
#define HAND_MS     2000        /* dock beam stays "blocked" this long after arriving */
#define BOOT_MS     2000

static const rt_uint8_t k_store[] = {
    UI_STEP_PULL_FROM_DOCK, UI_STEP_ROTATE_TO_BAY, UI_STEP_ENGAGE,
    UI_STEP_PUSH_INTO_BAY, UI_STEP_FORK_RETRACT, UI_STEP_PRESET_TRAY
};
static const rt_uint8_t k_get[] = {
    UI_STEP_RETURN_DOCK_TRAY, UI_STEP_ROTATE_TO_BAY, UI_STEP_PULL_FROM_BAY,
    UI_STEP_ROTATE_TO_DOCK, UI_STEP_PUSH_TO_DOCK
};
static const rt_uint8_t k_home[] = { UI_STEP_HOMING };

static struct ui_state s;
static const rt_uint8_t *s_steps;
static rt_tick_t s_t0;              /* start of the current phase / step */
static rt_int32_t s_cal[UI_LAYERS_MAX][UI_DIRS][2];
static rt_uint8_t s_inited;

static void sim_init(void)
{
    static const rt_uint8_t l1[UI_DIRS] = { UI_BAY_CAR, UI_BAY_TRAY, UI_BAY_CAR, UI_BAY_TRAY,
                                            UI_BAY_TRAY, UI_BAY_CAR, UI_BAY_TRAY, UI_BAY_TRAY };
    static const rt_uint8_t l2[UI_DIRS] = { UI_BAY_TRAY, UI_BAY_TRAY, UI_BAY_CAR, UI_BAY_TRAY,
                                            UI_BAY_TRAY, UI_BAY_TRAY, UI_BAY_NA, UI_BAY_TRAY };

    rt_memset(&s, 0, sizeof(s));
    s.phase = UI_PH_BOOT;
    s.layers = 2;
    rt_memcpy(s.bay[0], l1, UI_DIRS);
    rt_memcpy(s.bay[1], l2, UI_DIRS);
    s.lift_layer = 1;
    s.heading = UI_DIR_DOCK;
    s_t0 = rt_tick_get();
    s_inited = 1;
}

static void start_run(const rt_uint8_t *steps, rt_uint8_t n)
{
    s_steps = steps;
    s.step_total = n;
    s.step_idx = 1;
    s.step = steps[0];
    s.phase = UI_PH_RUN;
    s_t0 = rt_tick_get();
}

static void finish_run(void)
{
    if (s.job == UI_JOB_STORE) {
        s.bay[s.job_layer - 1][s.job_dir] = UI_BAY_CAR;
        s.job = UI_JOB_NONE;
        s.phase = UI_PH_READY;
    } else if (s.job == UI_JOB_RETRIEVE) {
        s.bay[s.job_layer - 1][s.job_dir] = UI_BAY_TRAY;
        s.phase = UI_PH_DOCK_TAKE;
    } else {
        s.phase = UI_PH_READY;
    }
    s.heading = UI_DIR_DOCK;
    s.step = UI_STEP_NONE;
    s_t0 = rt_tick_get();
}

static void advance(void)
{
    rt_tick_t now = rt_tick_get();
    rt_tick_t step = rt_tick_from_millisecond(STEP_MS);

    if (s.phase == UI_PH_BOOT && now - s_t0 > rt_tick_from_millisecond(BOOT_MS)) {
        s.phase = UI_PH_READY;
    } else if (s.phase == UI_PH_RUN) {
        while (s.phase == UI_PH_RUN && now - s_t0 >= step) {
            s_t0 += step;
            if (s.step_idx >= s.step_total) {
                finish_run();
            } else {
                s.step = s_steps[s.step_idx++];
                if (s.step == UI_STEP_ROTATE_TO_BAY)
                    s.heading = s.job_dir;
                else if (s.step == UI_STEP_ROTATE_TO_DOCK || s.step == UI_STEP_PRESET_TRAY)
                    s.heading = UI_DIR_DOCK;
            }
        }
        if (s.phase == UI_PH_RUN)
            s.eta_s = (rt_uint16_t)((s.step_total - s.step_idx + 1) * (STEP_MS / 1000));
    }

    /* Sensors derived from the fake state. */
    {
        rt_uint16_t sen = UI_SEN_FORK_IN | UI_SEN_BOARD1;
        int d;

        for (d = 0; d < UI_DIRS; d++)
            if (s.bay[0][d] == UI_BAY_TRAY || s.bay[0][d] == UI_BAY_CAR)
                sen |= UI_SEN_BAY(d);
        if (s.layers > 1)
            sen |= UI_SEN_BOARD2;
        if (s.phase != UI_PH_ESTOP)
            sen |= UI_SEN_ESTOP_OK;
        if ((s.phase == UI_PH_DOCK_PUT || s.phase == UI_PH_DOCK_TAKE) &&
            now - s_t0 < rt_tick_from_millisecond(HAND_MS))
            sen |= UI_SEN_DOCK_IR;
        s.sensors = sen;
    }
}

void garage_ui_get_state(struct ui_state *out)
{
    rt_base_t lv;

    if (!s_inited)
        sim_init();
    lv = rt_hw_interrupt_disable();
    advance();
    *out = s;
    rt_hw_interrupt_enable(lv);
}

int garage_ui_post_cmd(const struct ui_cmd *c)
{
    int l, d, ret = 0;
    rt_base_t lv = rt_hw_interrupt_disable();

    switch (c->id) {
    case UI_CMD_STORE:
        ret = -1;
        if (s.phase != UI_PH_READY)
            break;
        for (l = 0; l < s.layers && ret; l++) {
            for (d = 0; d < UI_DIRS; d++) {
                if (d != UI_DIR_DOCK && s.bay[l][d] == UI_BAY_TRAY) {
                    s.job = UI_JOB_STORE;
                    s.job_layer = (rt_uint8_t)(l + 1);
                    s.job_dir = (rt_uint8_t)d;
                    s.phase = UI_PH_DOCK_PUT;
                    s_t0 = rt_tick_get();
                    ret = 0;
                    break;
                }
            }
        }
        break;
    case UI_CMD_RETRIEVE:
        if (s.phase != UI_PH_READY || c->a < 1 || c->a > s.layers || c->b >= UI_DIRS ||
            s.bay[c->a - 1][c->b] != UI_BAY_CAR) {
            ret = -1;
            break;
        }
        s.job = UI_JOB_RETRIEVE;
        s.job_layer = c->a;
        s.job_dir = c->b;
        start_run(k_get, sizeof(k_get));
        break;
    case UI_CMD_CONFIRM_PUT:
        if (s.phase == UI_PH_DOCK_PUT)
            start_run(k_store, sizeof(k_store));
        else
            ret = -1;
        break;
    case UI_CMD_CANCEL:
        if (s.phase == UI_PH_DOCK_PUT) {
            s.job = UI_JOB_NONE;
            s.phase = UI_PH_READY;
        }
        break;
    case UI_CMD_TAKEN:
        if (s.phase == UI_PH_DOCK_TAKE) {
            s.job = UI_JOB_NONE;
            s.phase = UI_PH_READY;
        }
        break;
    case UI_CMD_FAULT_ACK:
        if (s.phase == UI_PH_FAULT) {
            s.fault = 0;
            s.job = UI_JOB_NONE;
            start_run(k_home, sizeof(k_home));
        }
        break;
    case UI_CMD_JOG:
        if (c->a < UI_AXIS__COUNT)
            s.axis_pos[c->a] += c->v;
        break;
    case UI_CMD_HOME_ALL:
        rt_memset(s.axis_pos, 0, sizeof(s.axis_pos));
        break;
    case UI_CMD_CAL_SAVE:
        if (c->a >= 1 && c->a <= UI_LAYERS_MAX && c->b < UI_DIRS) {
            s_cal[c->a - 1][c->b][0] = s.axis_pos[UI_AXIS_LIFT];
            s_cal[c->a - 1][c->b][1] = s.axis_pos[UI_AXIS_ROTATE];
        }
        break;
    default:
        ret = -1;
        break;
    }
    rt_hw_interrupt_enable(lv);
    return ret;
}

void garage_ui_get_cal(uint8_t layer, uint8_t dir, int32_t *lift_steps, int32_t *rot_steps)
{
    if (layer < 1 || layer > UI_LAYERS_MAX || dir >= UI_DIRS)
        return;
    *lift_steps = s_cal[layer - 1][dir][0];
    *rot_steps = s_cal[layer - 1][dir][1];
}

#ifdef RT_USING_FINSH
#include <finsh.h>

static int sim_fault(int argc, char **argv)
{
    if (argc != 2) {
        rt_kprintf("usage: sim_fault <code>\n");
        return -1;
    }
    s.fault = (rt_uint8_t)atoi(argv[1]);
    s.phase = UI_PH_FAULT;
    return 0;
}
MSH_CMD_EXPORT(sim_fault, simulate a garage fault on the screen);

static int sim_estop(int argc, char **argv)
{
    if (argc != 2) {
        rt_kprintf("usage: sim_estop <0|1>\n");
        return -1;
    }
    if (atoi(argv[1])) {
        s.phase = UI_PH_ESTOP;
    } else if (s.phase == UI_PH_ESTOP) {
        s.fault = 1;                /* position unknown after an emergency stop */
        s.phase = UI_PH_FAULT;
    }
    return 0;
}
MSH_CMD_EXPORT(sim_estop, simulate the emergency stop button);
#endif

#endif /* HMI_USING_SIM */
