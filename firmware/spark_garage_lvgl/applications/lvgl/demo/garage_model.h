/*
 * Tower-garage demo state machine.
 *
 * One layer, 8 compass slots. Index 6 is the south DOCK and is not a
 * storage bay. Cars and empty bays are counted on the other seven only.
 * A car always sits on a tray. Dock may be empty, an empty tray, or a car.
 *
 * Park: a tray must be on the dock before the user confirms. If it is not,
 * the nearest storage tray is fetched first and stays there when the user
 * backs out. After the car is seated, one remaining empty tray is preset
 * back onto the dock.
 *
 * Get: a car already on the dock blocks the job. An empty tray on the dock
 * is returned to an empty storage bay before the chosen car is delivered.
 * After delivery the user confirms departure; the tray stays on the dock.
 *
 * The job does not write bay[] until it finishes. Abort restores the
 * snapshot taken when the job started. garage_model_bay_view() is only a
 * progress picture for the ring.
 */

#ifndef GARAGE_MODEL_H
#define GARAGE_MODEL_H

#include <stddef.h>
#include <stdint.h>

#define GARAGE_BAY_COUNT 8
#define GARAGE_DIR_DOCK  6
#define GARAGE_STORE_N   7
#define GARAGE_MENU_N    3

typedef enum {
    BAY_EMPTY = 0,
    BAY_TRAY = 1,
    BAY_CAR = 2
} bay_state_t;

typedef enum {
    PAGE_IDLE = 0,
    PAGE_MENU,
    PAGE_PARK,
    PAGE_GET,
    PAGE_PROG,
    PAGE_FAULT
} page_id_t;

typedef enum {
    JOB_NONE = 0,
    JOB_PARK,
    JOB_GET
} job_kind_t;

typedef enum {
    KEY_NONE = 0,
    KEY_LEFT,
    KEY_RIGHT,
    KEY_UP,
    KEY_DOWN
} key_id_t;

typedef enum {
    FAULT_NONE = 0,
    FAULT_NO_EMPTY, /* E01 storage has nowhere to seat a car */
    FAULT_DOCK_CAR, /* E02 a car is still on the dock */
    FAULT_NO_TRAY,  /* E03 no empty tray can be fetched */
    FAULT_NO_CAR,   /* E04 no stored car */
    FAULT_NO_STASH  /* E05 dock tray has no empty bay to return to */
} fault_id_t;

typedef enum {
    BLOCK_READY = 0,
    BLOCK_FETCH, /* park can start, but a tray must be fetched first */
    BLOCK_DOCK_CAR,
    BLOCK_NO_EMPTY,
    BLOCK_NO_TRAY,
    BLOCK_NO_CAR,
    BLOCK_NO_STASH
} garage_block_t;

typedef enum {
    PARK_DOCK = 0, /* ask the user to drive onto the dock tray */
    PARK_PICK = 1  /* choose the empty storage bay */
} park_phase_t;

typedef enum {
    PROG_RUN = 0,
    PROG_HOLD = 1
} prog_phase_t;

typedef enum {
    NOTE_NONE = 0,
    NOTE_TOP,
    NOTE_BOTTOM,
    NOTE_BUSY,
    NOTE_BLOCKED
} garage_note_t;

typedef struct {
    bay_state_t bay[GARAGE_BAY_COUNT];
    page_id_t page;
    int menu;
    park_phase_t park_phase;
    int park_i;
    int park_map[GARAGE_STORE_N];
    int park_n;
    int get_i;
    int get_map[GARAGE_STORE_N];
    int get_n;
    job_kind_t job;
    int job_target;
    int job_stash;
    int prog;
    prog_phase_t prog_phase;
    int hold_ticks;
    fault_id_t fault;
    garage_note_t note;
    bay_state_t snap[GARAGE_BAY_COUNT];
    int snap_valid;
} garage_model_t;

void garage_model_init(garage_model_t *m);

int garage_count_cars(const garage_model_t *m);
int garage_count_empty(const garage_model_t *m);
int garage_count_trays(const garage_model_t *m);
bay_state_t garage_dock(const garage_model_t *m);

/* Storage bays only, nearest-to-dock preference. -1 when none. */
int garage_best_empty(const garage_model_t *m);
int garage_best_tray(const garage_model_t *m);

garage_block_t garage_park_block(const garage_model_t *m);
garage_block_t garage_get_block(const garage_model_t *m);

const char *garage_bay_name(int index);
const char *garage_bay_short(int index);

bay_state_t garage_model_bay_view(const garage_model_t *m, int index);
int garage_model_focus_bay(const garage_model_t *m);
int garage_model_step_index(const garage_model_t *m);
void garage_model_step_line(const garage_model_t *m, char *buf, size_t n);

const char *garage_fault_code(fault_id_t fault);
const char *garage_fault_title(fault_id_t fault);
const char *garage_fault_body(fault_id_t fault);
const char *garage_fault_action(const garage_model_t *m);

void garage_model_on_key(garage_model_t *m, key_id_t key);

/* 0: still running. 1: just committed and holding. 2: left the progress page. */
int garage_model_job_tick(garage_model_t *m);

int garage_model_allow_idle_timeout(const garage_model_t *m);
void garage_model_on_idle_timeout(garage_model_t *m);

#endif /* GARAGE_MODEL_H */
