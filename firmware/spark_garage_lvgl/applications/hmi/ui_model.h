/*
 * ui_model.h - interface between the garage core (scheduler) and any UI backend.
 *
 * The core only fills a ui_state snapshot and accepts ui_cmd commands.
 * The TJC serial screen backend (hmi_tjc.c) and the on-board LVGL debug
 * screen can both be built on top of this without touching the core.
 */
#ifndef UI_MODEL_H
#define UI_MODEL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UI_LAYERS_MAX   2
#define UI_DIRS         8

/* Direction index. Order is fixed: it is also the b0..b7 control order on the screen. */
enum ui_dir {
    UI_DIR_E = 0, UI_DIR_NE, UI_DIR_N, UI_DIR_NW,
    UI_DIR_W, UI_DIR_SW, UI_DIR_S, UI_DIR_SE
};
#define UI_DIR_DOCK     UI_DIR_S        /* 1F south = dock, 2F south = shaft */

enum ui_bay {
    UI_BAY_EMPTY = 0,   /* no tray */
    UI_BAY_TRAY,        /* tray without car */
    UI_BAY_CAR,         /* tray with car */
    UI_BAY_NA           /* not a bay (2F shaft) */
};

enum ui_phase {
    UI_PH_BOOT = 0,     /* self test / layer scan, not ready */
    UI_PH_READY,        /* idle, accepts store / retrieve */
    UI_PH_DOCK_PUT,     /* waiting for the user to put the car and confirm */
    UI_PH_DOCK_TAKE,    /* waiting for the user to take the car and confirm */
    UI_PH_RUN,          /* job is moving */
    UI_PH_FAULT,        /* stopped, waiting for manual confirmation */
    UI_PH_ESTOP         /* emergency stop pressed */
};

enum ui_job { UI_JOB_NONE = 0, UI_JOB_STORE, UI_JOB_RETRIEVE };

/* Step shown on the progress page. Text for each id lives in hmi_text.h. */
enum ui_step {
    UI_STEP_NONE = 0,
    UI_STEP_FETCH_TRAY,         /* bring an empty tray to the dock */
    UI_STEP_PULL_FROM_DOCK,
    UI_STEP_ROTATE_TO_BAY,      /* text includes the direction name */
    UI_STEP_LIFT_TO_LAYER,
    UI_STEP_ENGAGE,
    UI_STEP_PUSH_INTO_BAY,
    UI_STEP_FORK_RETRACT,
    UI_STEP_PRESET_TRAY,
    UI_STEP_RETURN_DOCK_TRAY,
    UI_STEP_PULL_FROM_BAY,
    UI_STEP_ROTATE_TO_DOCK,
    UI_STEP_PUSH_TO_DOCK,
    UI_STEP_HOMING,
    UI_STEP__COUNT
};

/* Sensor bits shown on the maintenance page (lamp l0..l15). */
#define UI_SEN_BAY(d)       (1u << (d))     /* 1F bay hall, d = enum ui_dir */
#define UI_SEN_CARRIAGE     (1u << 8)
#define UI_SEN_FORK_IN      (1u << 9)
#define UI_SEN_FORK_OUT     (1u << 10)
#define UI_SEN_LIFT_LOW     (1u << 11)
#define UI_SEN_DOCK_IR      (1u << 12)      /* 1 = beam blocked */
#define UI_SEN_ESTOP_OK     (1u << 13)      /* 1 = loop closed */
#define UI_SEN_BOARD1       (1u << 14)      /* MCP23017 0x20 answers */
#define UI_SEN_BOARD2       (1u << 15)      /* MCP23017 0x21 answers */

enum ui_axis { UI_AXIS_LIFT = 0, UI_AXIS_ROTATE, UI_AXIS_FORK, UI_AXIS__COUNT };

struct ui_state {
    uint8_t  phase;                         /* enum ui_phase */
    uint8_t  layers;                        /* 1 or 2, from I2C scan */
    uint8_t  bay[UI_LAYERS_MAX][UI_DIRS];   /* enum ui_bay, [layer-1][dir] */

    uint8_t  lift_layer;                    /* carriage layer, 1..layers; 0 = unknown */
    uint8_t  heading;                       /* enum ui_dir the fork points to */

    uint8_t  job;                           /* enum ui_job */
    uint8_t  job_layer;                     /* 1..2 */
    uint8_t  job_dir;                       /* enum ui_dir */
    uint8_t  step;                          /* enum ui_step */
    uint8_t  step_idx;                      /* 1..step_total */
    uint8_t  step_total;
    uint16_t eta_s;                         /* remaining seconds, estimate */

    uint8_t  fault;                         /* fault code, shown as "Exx"; 0 = none */

    uint16_t sensors;                       /* UI_SEN_* */
    int32_t  axis_pos[UI_AXIS__COUNT];      /* steps */
};

enum ui_cmd_id {
    UI_CMD_STORE = 1,       /* user pressed "store" */
    UI_CMD_RETRIEVE,        /* a = layer (1..2), b = dir */
    UI_CMD_CONFIRM_PUT,     /* car is on the tray, go */
    UI_CMD_CANCEL,          /* cancel store before the car is put */
    UI_CMD_TAKEN,           /* car was taken from the dock */
    UI_CMD_FAULT_ACK,       /* both manual checks ticked: re-home and resume */
    UI_CMD_JOG,             /* a = enum ui_axis, v = signed steps */
    UI_CMD_HOME_ALL,
    UI_CMD_CAL_SAVE         /* a = layer, b = dir: store current lift/rotate position */
};

struct ui_cmd {
    uint8_t id;             /* enum ui_cmd_id */
    uint8_t a;
    uint8_t b;
    int32_t v;
};

/*
 * Implemented by the garage core (or by ui_sim.c until the core exists).
 * Both are called from the UI thread and must not block.
 */
void garage_ui_get_state(struct ui_state *out);
int  garage_ui_post_cmd(const struct ui_cmd *cmd);      /* 0 = accepted */
/* Saved calibration for one bay, for the calibration page. */
void garage_ui_get_cal(uint8_t layer, uint8_t dir, int32_t *lift_steps, int32_t *rot_steps);

#ifdef __cplusplus
}
#endif

#endif /* UI_MODEL_H */
