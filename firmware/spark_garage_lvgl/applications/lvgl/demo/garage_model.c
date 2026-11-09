#include "garage_model.h"

#include <stdio.h>
#include <string.h>

/* SE, SW, E, W, NE, NW, N. Dock (south) is not a candidate. */
static const int k_pref[GARAGE_STORE_N] = { 7, 5, 0, 4, 1, 3, 2 };

static const char *const k_name[GARAGE_BAY_COUNT] = {
    "东", "东北", "北", "西北", "西", "西南", "对接", "东南"
};
static const char *const k_short[GARAGE_BAY_COUNT] = {
    "E", "NE", "N", "NW", "W", "SW", "DK", "SE"
};

static int count_if(const garage_model_t *m, bay_state_t want, int skip_dock)
{
    int n = 0;
    int i;

    for (i = 0; i < GARAGE_BAY_COUNT; i++) {
        if (skip_dock && i == GARAGE_DIR_DOCK) continue;
        if (m->bay[i] == want) n++;
    }
    return n;
}

static int best_where(const garage_model_t *m, bay_state_t want)
{
    int i;

    for (i = 0; i < GARAGE_STORE_N; i++) {
        if (m->bay[k_pref[i]] == want) return k_pref[i];
    }
    return -1;
}

static void rebuild(const garage_model_t *m, bay_state_t want, int *map, int *n)
{
    int i;
    int c = 0;

    for (i = 0; i < GARAGE_BAY_COUNT; i++) {
        if (i == GARAGE_DIR_DOCK) continue;
        if (m->bay[i] == want) map[c++] = i;
    }
    *n = c;
}

static int map_index(const int *map, int n, int bay)
{
    int i;

    for (i = 0; i < n; i++) {
        if (map[i] == bay) return i;
    }
    return 0;
}

static void enter_fault(garage_model_t *m, fault_id_t fault)
{
    m->fault = fault;
    m->job = JOB_NONE;
    m->prog_phase = PROG_RUN;
    m->page = PAGE_FAULT;
}

static void enter_menu(garage_model_t *m)
{
    m->job = JOB_NONE;
    m->prog_phase = PROG_RUN;
    m->snap_valid = 0;
    m->fault = FAULT_NONE;
    m->page = PAGE_MENU;
}

static void enter_idle(garage_model_t *m)
{
    m->page = PAGE_IDLE;
    m->park_phase = PARK_DOCK;
    m->fault = FAULT_NONE;
}

static int clamp_move(int index, int n, int dir, garage_note_t *note)
{
    int next;

    if (n <= 1) {
        *note = (dir < 0) ? NOTE_TOP : NOTE_BOTTOM;
        return 0;
    }
    next = index + dir;
    if (next < 0) {
        *note = NOTE_TOP;
        return 0;
    }
    if (next >= n) {
        *note = NOTE_BOTTOM;
        return n - 1;
    }
    return next;
}

static void open_park(garage_model_t *m)
{
    garage_block_t block = garage_park_block(m);
    int tray;
    int best;

    if (block == BLOCK_DOCK_CAR) {
        enter_fault(m, FAULT_DOCK_CAR);
        return;
    }
    if (block == BLOCK_NO_TRAY) {
        enter_fault(m, FAULT_NO_TRAY);
        return;
    }
    if (block == BLOCK_NO_EMPTY) {
        enter_fault(m, FAULT_NO_EMPTY);
        return;
    }
    if (block == BLOCK_FETCH) {
        tray = garage_best_tray(m);
        if (tray < 0) {
            enter_fault(m, FAULT_NO_TRAY);
            return;
        }
        m->bay[tray] = BAY_EMPTY;
        m->bay[GARAGE_DIR_DOCK] = BAY_TRAY;
    }
    if (garage_count_empty(m) <= 0) {
        enter_fault(m, FAULT_NO_EMPTY);
        return;
    }

    rebuild(m, BAY_EMPTY, m->park_map, &m->park_n);
    best = garage_best_empty(m);
    m->park_i = map_index(m->park_map, m->park_n, best);
    m->park_phase = PARK_DOCK;
    m->fault = FAULT_NONE;
    m->page = PAGE_PARK;
}

static void open_get(garage_model_t *m)
{
    garage_block_t block = garage_get_block(m);

    if (block == BLOCK_DOCK_CAR) {
        enter_fault(m, FAULT_DOCK_CAR);
        return;
    }
    if (block == BLOCK_NO_CAR) {
        enter_fault(m, FAULT_NO_CAR);
        return;
    }
    if (block == BLOCK_NO_STASH) {
        enter_fault(m, FAULT_NO_STASH);
        return;
    }

    rebuild(m, BAY_CAR, m->get_map, &m->get_n);
    if (m->get_n <= 0) {
        enter_fault(m, FAULT_NO_CAR);
        return;
    }
    m->get_i = 0;
    m->fault = FAULT_NONE;
    m->page = PAGE_GET;
}

static void begin_job(garage_model_t *m, job_kind_t kind, int target, int stash)
{
    memcpy(m->snap, m->bay, sizeof m->bay);
    m->snap_valid = 1;
    m->job = kind;
    m->job_target = target;
    m->job_stash = stash;
    m->prog = 0;
    m->hold_ticks = 0;
    m->prog_phase = PROG_RUN;
    m->fault = FAULT_NONE;
    m->page = PAGE_PROG;
}

static void abort_job(garage_model_t *m)
{
    if (m->snap_valid) memcpy(m->bay, m->snap, sizeof m->bay);
    m->snap_valid = 0;
    m->job = JOB_NONE;
    m->prog = 0;
    m->prog_phase = PROG_RUN;
    m->page = PAGE_MENU;
}

static int commit_park(garage_model_t *m)
{
    int target = m->job_target;
    int tray;

    if (target < 0 || target >= GARAGE_BAY_COUNT || target == GARAGE_DIR_DOCK) return 0;
    if (m->bay[target] != BAY_EMPTY) return 0;
    if (m->bay[GARAGE_DIR_DOCK] != BAY_TRAY) return 0;

    m->bay[GARAGE_DIR_DOCK] = BAY_EMPTY;
    m->bay[target] = BAY_CAR;
    tray = garage_best_tray(m);
    if (tray >= 0) {
        m->bay[tray] = BAY_EMPTY;
        m->bay[GARAGE_DIR_DOCK] = BAY_TRAY;
    }
    return 1;
}

static int commit_get(garage_model_t *m)
{
    int target = m->job_target;
    int stash = m->job_stash;

    if (target < 0 || target >= GARAGE_BAY_COUNT || target == GARAGE_DIR_DOCK) return 0;
    if (m->bay[target] != BAY_CAR) return 0;

    if (stash >= 0) {
        if (stash == target || stash == GARAGE_DIR_DOCK) return 0;
        if (m->bay[stash] != BAY_EMPTY) return 0;
        if (m->bay[GARAGE_DIR_DOCK] != BAY_TRAY) return 0;
        m->bay[stash] = BAY_TRAY;
    } else if (m->bay[GARAGE_DIR_DOCK] != BAY_EMPTY) {
        return 0;
    }

    m->bay[target] = BAY_EMPTY;
    m->bay[GARAGE_DIR_DOCK] = BAY_CAR;
    return 1;
}

static void fault_right(garage_model_t *m)
{
    if (m->fault == FAULT_DOCK_CAR) {
        if (m->bay[GARAGE_DIR_DOCK] == BAY_CAR) m->bay[GARAGE_DIR_DOCK] = BAY_TRAY;
        m->menu = 0;
        enter_menu(m);
        return;
    }
    if (m->fault == FAULT_NO_EMPTY) {
        m->note = NOTE_BLOCKED;
        return;
    }
    if (m->fault == FAULT_NO_TRAY) {
        if (garage_count_cars(m) <= 0) {
            m->note = NOTE_BLOCKED;
            return;
        }
        open_get(m);
        return;
    }
    if (m->fault == FAULT_NO_CAR) {
        open_park(m);
        return;
    }
    m->note = NOTE_BLOCKED;
}

static void menu_ok(garage_model_t *m)
{
    if (m->menu == 0) {
        open_park(m);
    } else if (m->menu == 1) {
        open_get(m);
    } else if (garage_dock(m) == BAY_CAR) {
        m->bay[GARAGE_DIR_DOCK] = BAY_TRAY;
        m->menu = 0;
        m->page = PAGE_MENU;
    } else {
        enter_idle(m);
    }
}

static void park_key(garage_model_t *m, key_id_t key)
{
    int target;

    if (m->park_phase == PARK_DOCK) {
        if (key == KEY_RIGHT) {
            rebuild(m, BAY_EMPTY, m->park_map, &m->park_n);
            if (m->park_n <= 0) {
                enter_fault(m, FAULT_NO_EMPTY);
                return;
            }
            m->park_i = map_index(m->park_map, m->park_n, garage_best_empty(m));
            m->park_phase = PARK_PICK;
        } else if (key == KEY_LEFT) {
            enter_menu(m);
        } else {
            m->note = NOTE_BLOCKED;
        }
        return;
    }

    if (key == KEY_UP) {
        m->park_i = clamp_move(m->park_i, m->park_n, -1, &m->note);
    } else if (key == KEY_DOWN) {
        m->park_i = clamp_move(m->park_i, m->park_n, 1, &m->note);
    } else if (key == KEY_LEFT) {
        m->park_phase = PARK_DOCK;
    } else if (key == KEY_RIGHT) {
        if (m->park_n <= 0) {
            enter_fault(m, FAULT_NO_EMPTY);
            return;
        }
        target = m->park_map[m->park_i];
        if (m->bay[target] != BAY_EMPTY || m->bay[GARAGE_DIR_DOCK] != BAY_TRAY) {
            enter_fault(m, m->bay[GARAGE_DIR_DOCK] == BAY_CAR ? FAULT_DOCK_CAR : FAULT_NO_EMPTY);
            return;
        }
        begin_job(m, JOB_PARK, target, -1);
    }
}

static void get_key(garage_model_t *m, key_id_t key)
{
    int target;
    int stash;

    if (key == KEY_UP) {
        m->get_i = clamp_move(m->get_i, m->get_n, -1, &m->note);
    } else if (key == KEY_DOWN) {
        m->get_i = clamp_move(m->get_i, m->get_n, 1, &m->note);
    } else if (key == KEY_LEFT) {
        enter_menu(m);
    } else if (key == KEY_RIGHT) {
        if (m->get_n <= 0) {
            m->note = NOTE_BLOCKED;
            return;
        }
        target = m->get_map[m->get_i];
        if (m->bay[GARAGE_DIR_DOCK] == BAY_CAR) {
            enter_fault(m, FAULT_DOCK_CAR);
            return;
        }
        if (m->bay[target] != BAY_CAR) {
            enter_fault(m, FAULT_NO_CAR);
            return;
        }
        stash = -1;
        if (m->bay[GARAGE_DIR_DOCK] == BAY_TRAY) {
            stash = garage_best_empty(m);
            if (stash < 0) {
                enter_fault(m, FAULT_NO_STASH);
                return;
            }
        } else if (m->bay[GARAGE_DIR_DOCK] != BAY_EMPTY) {
            m->note = NOTE_BLOCKED;
            return;
        }
        begin_job(m, JOB_GET, target, stash);
    }
}

static void prog_key(garage_model_t *m, key_id_t key)
{
    if (m->prog_phase == PROG_RUN) {
        if (key == KEY_LEFT) abort_job(m);
        else m->note = NOTE_BUSY;
        return;
    }

    if (m->job == JOB_GET) {
        if (key == KEY_RIGHT) {
            if (m->bay[GARAGE_DIR_DOCK] == BAY_CAR) m->bay[GARAGE_DIR_DOCK] = BAY_TRAY;
            m->menu = 0;
            enter_menu(m);
        } else if (key == KEY_LEFT) {
            enter_menu(m);
        } else {
            m->note = NOTE_BLOCKED;
        }
        return;
    }

    enter_menu(m);
}

void garage_model_init(garage_model_t *m)
{
    static const bay_state_t seed[GARAGE_BAY_COUNT] = {
        BAY_TRAY, BAY_CAR, BAY_TRAY, BAY_EMPTY,
        BAY_CAR, BAY_TRAY, BAY_TRAY, BAY_EMPTY
    };

    memset(m, 0, sizeof *m);
    memcpy(m->bay, seed, sizeof seed);
    m->page = PAGE_IDLE;
    m->job_target = -1;
    m->job_stash = -1;
}

int garage_count_cars(const garage_model_t *m)
{
    return count_if(m, BAY_CAR, 1);
}

int garage_count_empty(const garage_model_t *m)
{
    return count_if(m, BAY_EMPTY, 1);
}

int garage_count_trays(const garage_model_t *m)
{
    return count_if(m, BAY_TRAY, 1);
}

bay_state_t garage_dock(const garage_model_t *m)
{
    return m->bay[GARAGE_DIR_DOCK];
}

int garage_best_empty(const garage_model_t *m)
{
    return best_where(m, BAY_EMPTY);
}

int garage_best_tray(const garage_model_t *m)
{
    return best_where(m, BAY_TRAY);
}

garage_block_t garage_park_block(const garage_model_t *m)
{
    if (m->bay[GARAGE_DIR_DOCK] == BAY_CAR) return BLOCK_DOCK_CAR;
    if (m->bay[GARAGE_DIR_DOCK] == BAY_EMPTY) {
        if (garage_count_trays(m) <= 0) return BLOCK_NO_TRAY;
        return BLOCK_FETCH;
    }
    if (garage_count_empty(m) <= 0) return BLOCK_NO_EMPTY;
    return BLOCK_READY;
}

garage_block_t garage_get_block(const garage_model_t *m)
{
    if (m->bay[GARAGE_DIR_DOCK] == BAY_CAR) return BLOCK_DOCK_CAR;
    if (garage_count_cars(m) <= 0) return BLOCK_NO_CAR;
    if (m->bay[GARAGE_DIR_DOCK] == BAY_TRAY && garage_count_empty(m) <= 0) return BLOCK_NO_STASH;
    return BLOCK_READY;
}

const char *garage_bay_name(int index)
{
    if (index < 0 || index >= GARAGE_BAY_COUNT) return "--";
    return k_name[index];
}

const char *garage_bay_short(int index)
{
    if (index < 0 || index >= GARAGE_BAY_COUNT) return "--";
    return k_short[index];
}

bay_state_t garage_model_bay_view(const garage_model_t *m, int index)
{
    if (index < 0 || index >= GARAGE_BAY_COUNT) return BAY_EMPTY;
    if (m->page != PAGE_PROG || m->prog_phase != PROG_RUN || m->job == JOB_NONE)
        return m->bay[index];

    if (m->job == JOB_PARK) {
        if (index == GARAGE_DIR_DOCK) return (m->prog < 50) ? BAY_CAR : BAY_EMPTY;
        if (index == m->job_target && m->prog >= 75) return BAY_CAR;
        return m->bay[index];
    }

    if (m->job == JOB_GET) {
        if (index == GARAGE_DIR_DOCK && m->prog >= 75) return BAY_CAR;
        if (index == GARAGE_DIR_DOCK && m->job_stash >= 0) return BAY_EMPTY;
        if (m->job_stash >= 0 && index == m->job_stash && m->prog >= 25) return BAY_TRAY;
        if (index == m->job_target && m->prog >= 50) return BAY_EMPTY;
        return m->bay[index];
    }

    return m->bay[index];
}

int garage_model_focus_bay(const garage_model_t *m)
{
    if (m->page == PAGE_PARK) {
        if (m->park_phase == PARK_DOCK) return GARAGE_DIR_DOCK;
        if (m->park_n <= 0) return -1;
        return m->park_map[m->park_i];
    }
    if (m->page != PAGE_PROG || m->job == JOB_NONE) return -1;
    if (m->prog_phase == PROG_HOLD)
        return (m->job == JOB_GET) ? GARAGE_DIR_DOCK : m->job_target;
    if (m->job == JOB_PARK)
        return (m->prog < 50) ? GARAGE_DIR_DOCK : m->job_target;
    if (m->job_stash >= 0 && m->prog < 25) return m->job_stash;
    if (m->prog >= 75) return GARAGE_DIR_DOCK;
    return m->job_target;
}

int garage_model_step_index(const garage_model_t *m)
{
    int step;

    if (m->prog_phase == PROG_HOLD || m->prog >= 100) return 3;
    step = m->prog / 25;
    if (step < 0) step = 0;
    if (step > 3) step = 3;
    return step;
}

void garage_model_step_line(const garage_model_t *m, char *buf, size_t n)
{
    int step;
    const char *target;
    const char *stash;

    if (!buf || n == 0) return;
    buf[0] = '\0';
    if (m->job == JOB_NONE) return;

    target = garage_bay_name(m->job_target);
    stash = garage_bay_name(m->job_stash);

    if (m->prog_phase == PROG_HOLD) {
        if (m->job == JOB_PARK) {
            if (m->bay[GARAGE_DIR_DOCK] == BAY_TRAY)
                snprintf(buf, n, "已入库  托盘已预置");
            else
                snprintf(buf, n, "已入库  对接空出");
        } else {
            snprintf(buf, n, "请取走车辆");
        }
        return;
    }

    step = garage_model_step_index(m);
    if (m->job == JOB_PARK) {
        if (step == 0) snprintf(buf, n, "旋转对准对接");
        else if (step == 1) snprintf(buf, n, "拨叉拖入载车");
        else if (step == 2) snprintf(buf, n, "转至%s", target);
        else snprintf(buf, n, "推入并脱开");
        return;
    }

    if (m->job_stash >= 0) {
        if (step == 0) snprintf(buf, n, "送回托盘至%s", stash);
        else if (step == 1) snprintf(buf, n, "旋转对准%s", target);
        else if (step == 2) snprintf(buf, n, "拨叉取出");
        else snprintf(buf, n, "送达对接位");
        return;
    }

    if (step == 0) snprintf(buf, n, "旋转对准%s", target);
    else if (step == 1) snprintf(buf, n, "升降啮合");
    else if (step == 2) snprintf(buf, n, "拨叉取出");
    else snprintf(buf, n, "送达对接位");
}

const char *garage_fault_code(fault_id_t fault)
{
    switch (fault) {
    case FAULT_NO_EMPTY: return "E01";
    case FAULT_DOCK_CAR: return "E02";
    case FAULT_NO_TRAY: return "E03";
    case FAULT_NO_CAR: return "E04";
    case FAULT_NO_STASH: return "E05";
    default: return "E00";
    }
}

const char *garage_fault_title(fault_id_t fault)
{
    switch (fault) {
    case FAULT_NO_EMPTY: return "无空车位";
    case FAULT_DOCK_CAR: return "对接有车";
    case FAULT_NO_TRAY: return "无空托盘";
    case FAULT_NO_CAR: return "库内无车";
    case FAULT_NO_STASH: return "无法暂存";
    default: return "故障";
    }
}

const char *garage_fault_body(fault_id_t fault)
{
    switch (fault) {
    case FAULT_NO_EMPTY: return "车位已满 托盘无法让出";
    case FAULT_DOCK_CAR: return "车辆还停在对接位";
    case FAULT_NO_TRAY: return "库内没有空托盘";
    case FAULT_NO_CAR: return "没有可取的车辆";
    case FAULT_NO_STASH: return "对接托盘无处安放";
    default: return "";
    }
}

const char *garage_fault_action(const garage_model_t *m)
{
    switch (m->fault) {
    case FAULT_DOCK_CAR:
        return "右键确认已驶离";
    case FAULT_NO_EMPTY:
        return "左键返回菜单";
    case FAULT_NO_TRAY:
        return (garage_count_cars(m) > 0) ? "右键改为取车" : "左键返回菜单";
    case FAULT_NO_CAR:
        return "右键改为存车";
    case FAULT_NO_STASH:
        return "左键返回菜单";
    default:
        return "左键返回菜单";
    }
}

void garage_model_on_key(garage_model_t *m, key_id_t key)
{
    if (key == KEY_NONE) return;
    m->note = NOTE_NONE;

    switch (m->page) {
    case PAGE_IDLE:
        m->menu = 0;
        m->page = PAGE_MENU;
        break;

    case PAGE_MENU:
        if (key == KEY_UP) m->menu = clamp_move(m->menu, GARAGE_MENU_N, -1, &m->note);
        else if (key == KEY_DOWN) m->menu = clamp_move(m->menu, GARAGE_MENU_N, 1, &m->note);
        else if (key == KEY_RIGHT) menu_ok(m);
        else if (key == KEY_LEFT) enter_idle(m);
        break;

    case PAGE_PARK:
        park_key(m, key);
        break;

    case PAGE_GET:
        get_key(m, key);
        break;

    case PAGE_PROG:
        prog_key(m, key);
        break;

    case PAGE_FAULT:
        if (key == KEY_RIGHT) fault_right(m);
        else if (key == KEY_LEFT) enter_menu(m);
        else m->note = NOTE_BLOCKED;
        break;
    }
}

int garage_model_job_tick(garage_model_t *m)
{
    int committed;

    if (m->job == JOB_NONE) return 0;

    if (m->prog_phase == PROG_HOLD) {
        m->hold_ticks++;
        if (m->job == JOB_PARK && m->hold_ticks >= 8) {
            enter_menu(m);
            return 2;
        }
        return 0;
    }

    m->prog += 4;
    if (m->prog < 100) return 0;
    m->prog = 100;

    committed = (m->job == JOB_PARK) ? commit_park(m) : commit_get(m);
    if (!committed) {
        if (m->snap_valid) memcpy(m->bay, m->snap, sizeof m->bay);
        m->snap_valid = 0;
        enter_fault(m, FAULT_NO_EMPTY);
        return 2;
    }

    m->snap_valid = 0;
    m->prog_phase = PROG_HOLD;
    m->hold_ticks = 0;
    return 1;
}

int garage_model_allow_idle_timeout(const garage_model_t *m)
{
    if (m->job != JOB_NONE) return 0;
    if (m->page == PAGE_IDLE || m->page == PAGE_PROG) return 0;
    return 1;
}

void garage_model_on_idle_timeout(garage_model_t *m)
{
    if (!garage_model_allow_idle_timeout(m)) return;
    enter_idle(m);
    m->note = NOTE_NONE;
}
