/*
 * Host-side checks for the garage HMI state machine.
 *   gcc -std=c11 -Wall -Wextra -Werror -I applications/lvgl/demo \
 *     tests/test_garage_model.c applications/lvgl/demo/garage_model.c \
 *     -o /tmp/test_garage_model && /tmp/test_garage_model
 */

#include "garage_model.h"

#include <stdio.h>
#include <string.h>

static int g_fails;

static void check(int cond, const char *expr, const char *file, int line)
{
    if (cond) return;
    fprintf(stderr, "FAIL %s:%d  %s\n", file, line, expr);
    g_fails++;
}

#define CHECK(cond) check((cond), #cond, __FILE__, __LINE__)

static int tray_units(const garage_model_t *m)
{
    return garage_count_trays(m) + garage_count_cars(m)
        + (garage_dock(m) == BAY_TRAY ? 1 : 0)
        + (garage_dock(m) == BAY_CAR ? 1 : 0);
}

static void expect_bays(const garage_model_t *m, const bay_state_t *want, const char *tag)
{
    int i;

    for (i = 0; i < GARAGE_BAY_COUNT; i++) {
        if (m->bay[i] != want[i]) {
            fprintf(stderr, "FAIL %s bay[%d]=%d want %d\n", tag, i, m->bay[i], want[i]);
            g_fails++;
        }
    }
}

static void press(garage_model_t *m, key_id_t key)
{
    garage_model_on_key(m, key);
}

static int run_until_hold(garage_model_t *m)
{
    int guard = 0;

    while (m->page == PAGE_PROG && m->prog_phase == PROG_RUN && guard < 40) {
        garage_model_job_tick(m);
        guard++;
    }
    return guard;
}

static void test_seed_counts(void)
{
    garage_model_t m;

    garage_model_init(&m);
    CHECK(garage_count_cars(&m) == 2);
    CHECK(garage_count_empty(&m) == 2);
    CHECK(garage_count_trays(&m) == 3);
    CHECK(garage_dock(&m) == BAY_TRAY);
    CHECK(tray_units(&m) == 6);
    CHECK(garage_best_empty(&m) == 7);
    CHECK(garage_park_block(&m) == BLOCK_READY);
    CHECK(garage_get_block(&m) == BLOCK_READY);
    CHECK(strcmp(garage_bay_name(1), "东北") == 0);
    CHECK(strcmp(garage_bay_short(6), "DK") == 0);
    CHECK(strcmp(garage_bay_name(6), "对接") == 0);
}

static void test_dock_is_not_storage(void)
{
    garage_model_t m;

    garage_model_init(&m);
    m.bay[GARAGE_DIR_DOCK] = BAY_CAR;
    CHECK(garage_count_cars(&m) == 2);
    m.bay[GARAGE_DIR_DOCK] = BAY_EMPTY;
    CHECK(garage_count_empty(&m) == 2);
    m.bay[GARAGE_DIR_DOCK] = BAY_TRAY;
    CHECK(garage_count_trays(&m) == 3);
}

static void test_menu_clamps(void)
{
    garage_model_t m;

    garage_model_init(&m);
    press(&m, KEY_RIGHT);
    CHECK(m.page == PAGE_MENU);
    CHECK(m.menu == 0);
    press(&m, KEY_UP);
    CHECK(m.menu == 0);
    CHECK(m.note == NOTE_TOP);
    press(&m, KEY_DOWN);
    press(&m, KEY_DOWN);
    CHECK(m.menu == 2);
    press(&m, KEY_DOWN);
    CHECK(m.menu == 2);
    CHECK(m.note == NOTE_BOTTOM);
    press(&m, KEY_LEFT);
    CHECK(m.page == PAGE_IDLE);
}

static void test_home_and_depart(void)
{
    garage_model_t m;

    garage_model_init(&m);
    press(&m, KEY_UP);
    press(&m, KEY_DOWN);
    press(&m, KEY_DOWN);
    press(&m, KEY_RIGHT);
    CHECK(m.page == PAGE_IDLE);

    garage_model_init(&m);
    m.bay[GARAGE_DIR_DOCK] = BAY_CAR;
    press(&m, KEY_RIGHT);
    press(&m, KEY_DOWN);
    press(&m, KEY_DOWN);
    CHECK(m.menu == 2);
    press(&m, KEY_RIGHT);
    CHECK(m.page == PAGE_MENU);
    CHECK(m.menu == 0);
    CHECK(garage_dock(&m) == BAY_TRAY);
    CHECK(tray_units(&m) == 6);
}

static void test_demo_park_get_roundtrip(void)
{
    garage_model_t m;
    bay_state_t after_park[GARAGE_BAY_COUNT] = {
        BAY_TRAY, BAY_CAR, BAY_TRAY, BAY_EMPTY,
        BAY_CAR, BAY_EMPTY, BAY_TRAY, BAY_CAR
    };
    bay_state_t after_get[GARAGE_BAY_COUNT] = {
        BAY_TRAY, BAY_EMPTY, BAY_TRAY, BAY_EMPTY,
        BAY_CAR, BAY_TRAY, BAY_CAR, BAY_CAR
    };
    char line[64];
    bay_state_t real_target;
    int focus;

    garage_model_init(&m);
    press(&m, KEY_RIGHT);          /* idle -> menu */
    press(&m, KEY_RIGHT);          /* park, dock already has a tray */
    CHECK(m.page == PAGE_PARK);
    CHECK(m.park_phase == PARK_DOCK);
    CHECK(garage_dock(&m) == BAY_TRAY);
    CHECK(garage_model_focus_bay(&m) == GARAGE_DIR_DOCK);
    CHECK(tray_units(&m) == 6);

    press(&m, KEY_RIGHT);          /* confirm the car is on the tray */
    CHECK(m.park_phase == PARK_PICK);
    CHECK(m.park_n == 2);
    CHECK(m.park_map[0] == 3);
    CHECK(m.park_map[1] == 7);
    CHECK(m.park_i == 1);
    CHECK(garage_model_focus_bay(&m) == 7);

    press(&m, KEY_UP);
    CHECK(m.park_i == 0);
    CHECK(garage_model_focus_bay(&m) == 3);
    press(&m, KEY_DOWN);
    CHECK(m.park_i == 1);
    press(&m, KEY_DOWN);
    CHECK(m.note == NOTE_BOTTOM);
    CHECK(m.park_i == 1);

    press(&m, KEY_LEFT);           /* back to the dock prompt, no motion yet */
    CHECK(m.park_phase == PARK_DOCK);
    CHECK(m.bay[7] == BAY_EMPTY);

    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);          /* start */
    CHECK(m.page == PAGE_PROG);
    CHECK(m.job == JOB_PARK);
    CHECK(m.job_target == 7);
    CHECK(m.prog == 0);
    CHECK(garage_model_bay_view(&m, GARAGE_DIR_DOCK) == BAY_CAR);
    CHECK(m.bay[GARAGE_DIR_DOCK] == BAY_TRAY);
    garage_model_step_line(&m, line, sizeof line);
    CHECK(strcmp(line, "旋转对准对接") == 0);
    CHECK(garage_model_allow_idle_timeout(&m) == 0);

    while (m.prog < 48 && m.prog_phase == PROG_RUN) garage_model_job_tick(&m);
    CHECK(m.prog == 48);
    CHECK(garage_model_bay_view(&m, GARAGE_DIR_DOCK) == BAY_CAR);
    CHECK(m.bay[7] == BAY_EMPTY);
    garage_model_step_line(&m, line, sizeof line);
    CHECK(strcmp(line, "拨叉拖入载车") == 0);

    garage_model_job_tick(&m);
    CHECK(m.prog == 52);
    CHECK(garage_model_bay_view(&m, GARAGE_DIR_DOCK) == BAY_EMPTY);
    CHECK(garage_model_focus_bay(&m) == 7);
    garage_model_step_line(&m, line, sizeof line);
    CHECK(strcmp(line, "转至东南") == 0);

    while (m.prog < 76 && m.prog_phase == PROG_RUN) garage_model_job_tick(&m);
    CHECK(garage_model_bay_view(&m, 7) == BAY_CAR);
    real_target = m.bay[7];
    CHECK(real_target == BAY_EMPTY);
    garage_model_step_line(&m, line, sizeof line);
    CHECK(strcmp(line, "推入并脱开") == 0);

    CHECK(run_until_hold(&m) > 0);
    CHECK(m.prog_phase == PROG_HOLD);
    CHECK(m.page == PAGE_PROG);
    expect_bays(&m, after_park, "after park");
    CHECK(tray_units(&m) == 6);
    garage_model_step_line(&m, line, sizeof line);
    CHECK(strcmp(line, "已入库  托盘已预置") == 0);
    focus = garage_model_focus_bay(&m);
    CHECK(focus == 7);

    press(&m, KEY_RIGHT);
    CHECK(m.page == PAGE_MENU);
    CHECK(m.job == JOB_NONE);

    press(&m, KEY_DOWN);           /* 取车 */
    press(&m, KEY_RIGHT);
    CHECK(m.page == PAGE_GET);
    CHECK(m.get_n == 3);
    CHECK(m.get_map[0] == 1);
    CHECK(m.get_map[1] == 4);
    CHECK(m.get_map[2] == 7);
    CHECK(m.get_i == 0);

    press(&m, KEY_DOWN);
    press(&m, KEY_UP);
    CHECK(m.get_i == 0);
    press(&m, KEY_RIGHT);
    CHECK(m.page == PAGE_PROG);
    CHECK(m.job == JOB_GET);
    CHECK(m.job_target == 1);
    CHECK(m.job_stash == 5);
    CHECK(m.bay[1] == BAY_CAR);
    CHECK(garage_model_bay_view(&m, GARAGE_DIR_DOCK) == BAY_EMPTY);
    CHECK(garage_model_focus_bay(&m) == 5);
    garage_model_step_line(&m, line, sizeof line);
    CHECK(strcmp(line, "送回托盘至西南") == 0);

    while (m.prog < 28 && m.prog_phase == PROG_RUN) garage_model_job_tick(&m);
    CHECK(garage_model_bay_view(&m, 5) == BAY_TRAY);
    CHECK(m.bay[5] == BAY_EMPTY);

    while (m.prog < 52 && m.prog_phase == PROG_RUN) garage_model_job_tick(&m);
    CHECK(garage_model_bay_view(&m, 1) == BAY_EMPTY);
    CHECK(garage_model_focus_bay(&m) == 1);
    garage_model_step_line(&m, line, sizeof line);
    CHECK(strcmp(line, "拨叉取出") == 0);

    while (m.prog < 76 && m.prog_phase == PROG_RUN) garage_model_job_tick(&m);
    CHECK(garage_model_bay_view(&m, GARAGE_DIR_DOCK) == BAY_CAR);
    CHECK(m.bay[GARAGE_DIR_DOCK] == BAY_TRAY);
    garage_model_step_line(&m, line, sizeof line);
    CHECK(strcmp(line, "送达对接位") == 0);

    run_until_hold(&m);
    expect_bays(&m, after_get, "after get");
    CHECK(tray_units(&m) == 6);
    garage_model_step_line(&m, line, sizeof line);
    CHECK(strcmp(line, "请取走车辆") == 0);

    press(&m, KEY_UP);
    CHECK(m.page == PAGE_PROG);
    CHECK(m.note == NOTE_BLOCKED);
    press(&m, KEY_LEFT);           /* leave the car on the dock */
    CHECK(m.page == PAGE_MENU);
    CHECK(garage_dock(&m) == BAY_CAR);
    CHECK(garage_park_block(&m) == BLOCK_DOCK_CAR);
    CHECK(garage_get_block(&m) == BLOCK_DOCK_CAR);

    press(&m, KEY_RIGHT);          /* park is blocked */
    CHECK(m.page == PAGE_FAULT);
    CHECK(m.fault == FAULT_DOCK_CAR);
    CHECK(strcmp(garage_fault_code(m.fault), "E02") == 0);
    CHECK(strcmp(garage_fault_action(&m), "右键确认已驶离") == 0);
    press(&m, KEY_RIGHT);
    CHECK(m.page == PAGE_MENU);
    CHECK(garage_dock(&m) == BAY_TRAY);
    CHECK(m.menu == 0);
    CHECK(tray_units(&m) == 6);
}

static void test_abort_restores(void)
{
    garage_model_t m;
    bay_state_t before[GARAGE_BAY_COUNT];

    garage_model_init(&m);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    CHECK(m.page == PAGE_PROG);
    memcpy(before, m.bay, sizeof before);
    garage_model_job_tick(&m);
    garage_model_job_tick(&m);
    press(&m, KEY_RIGHT);
    CHECK(m.note == NOTE_BUSY);
    CHECK(m.page == PAGE_PROG);
    CHECK(memcmp(m.bay, before, sizeof before) == 0);
    press(&m, KEY_LEFT);
    CHECK(m.page == PAGE_MENU);
    CHECK(m.job == JOB_NONE);
    CHECK(memcmp(m.bay, before, sizeof before) == 0);
    CHECK(garage_model_allow_idle_timeout(&m) == 1);
}

static void test_fetch_tray_when_dock_empty(void)
{
    garage_model_t m;
    bay_state_t i;

    garage_model_init(&m);
    for (i = 0; i < GARAGE_BAY_COUNT; i++) m.bay[i] = BAY_CAR;
    m.bay[2] = BAY_TRAY;
    m.bay[1] = BAY_EMPTY;
    m.bay[GARAGE_DIR_DOCK] = BAY_EMPTY;
    CHECK(garage_park_block(&m) == BLOCK_FETCH);
    CHECK(garage_count_trays(&m) == 1);
    CHECK(garage_count_empty(&m) == 1);

    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    CHECK(m.page == PAGE_PARK);
    CHECK(m.bay[2] == BAY_EMPTY);
    CHECK(garage_dock(&m) == BAY_TRAY);
    CHECK(garage_count_empty(&m) == 2);
    press(&m, KEY_RIGHT);
    CHECK(m.park_phase == PARK_PICK);
    /* Preference hits NE (bay 1) before the bay the tray just left. */
    CHECK(garage_model_focus_bay(&m) == 1);
    press(&m, KEY_LEFT);
    press(&m, KEY_LEFT);
    CHECK(m.page == PAGE_MENU);
    CHECK(garage_dock(&m) == BAY_TRAY);
}

static void test_fetch_creates_the_only_empty(void)
{
    garage_model_t m;
    int i;

    garage_model_init(&m);
    for (i = 0; i < GARAGE_BAY_COUNT; i++) m.bay[i] = BAY_CAR;
    m.bay[0] = BAY_TRAY;
    m.bay[GARAGE_DIR_DOCK] = BAY_EMPTY;
    CHECK(garage_count_empty(&m) == 0);
    CHECK(garage_park_block(&m) == BLOCK_FETCH);

    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    CHECK(m.page == PAGE_PARK);
    CHECK(m.bay[0] == BAY_EMPTY);
    CHECK(garage_dock(&m) == BAY_TRAY);
    press(&m, KEY_RIGHT);
    CHECK(garage_model_focus_bay(&m) == 0);
    press(&m, KEY_RIGHT);
    run_until_hold(&m);
    CHECK(m.bay[0] == BAY_CAR);
    CHECK(garage_dock(&m) == BAY_EMPTY);
    CHECK(garage_count_trays(&m) == 0);
    CHECK(garage_count_cars(&m) == 7);
    CHECK(garage_park_block(&m) == BLOCK_NO_TRAY);
}

static void test_faults_and_recovery(void)
{
    garage_model_t m;
    int i;

    garage_model_init(&m);
    for (i = 0; i < GARAGE_BAY_COUNT; i++) {
        if (i == GARAGE_DIR_DOCK) m.bay[i] = BAY_TRAY;
        else m.bay[i] = BAY_CAR;
    }
    CHECK(garage_park_block(&m) == BLOCK_NO_EMPTY);
    CHECK(garage_get_block(&m) == BLOCK_NO_STASH);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    CHECK(m.fault == FAULT_NO_EMPTY);
    CHECK(strcmp(garage_fault_body(m.fault), "车位已满 托盘无法让出") == 0);
    CHECK(strcmp(garage_fault_action(&m), "左键返回菜单") == 0);
    press(&m, KEY_RIGHT);
    CHECK(m.note == NOTE_BLOCKED);
    CHECK(m.page == PAGE_FAULT);
    press(&m, KEY_LEFT);
    CHECK(m.page == PAGE_MENU);

    garage_model_init(&m);
    for (i = 0; i < GARAGE_BAY_COUNT; i++) m.bay[i] = BAY_EMPTY;
    m.bay[GARAGE_DIR_DOCK] = BAY_EMPTY;
    CHECK(garage_park_block(&m) == BLOCK_NO_TRAY);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    CHECK(m.fault == FAULT_NO_TRAY);
    CHECK(strcmp(garage_fault_action(&m), "左键返回菜单") == 0);
    press(&m, KEY_RIGHT);
    CHECK(m.note == NOTE_BLOCKED);
    CHECK(m.page == PAGE_FAULT);
    press(&m, KEY_LEFT);
    CHECK(m.page == PAGE_MENU);

    press(&m, KEY_DOWN);
    press(&m, KEY_RIGHT);
    CHECK(m.fault == FAULT_NO_CAR);
    CHECK(strcmp(garage_fault_code(m.fault), "E04") == 0);
    press(&m, KEY_RIGHT);
    CHECK(m.fault == FAULT_NO_TRAY);

    garage_model_init(&m);
    for (i = 0; i < GARAGE_BAY_COUNT; i++) m.bay[i] = BAY_CAR;
    m.bay[GARAGE_DIR_DOCK] = BAY_TRAY;
    /* Every storage bay is a car, so the dock tray has nowhere to go. */
    CHECK(garage_count_empty(&m) == 0);
    CHECK(garage_get_block(&m) == BLOCK_NO_STASH);
    press(&m, KEY_RIGHT);
    press(&m, KEY_DOWN);
    press(&m, KEY_RIGHT);
    CHECK(m.fault == FAULT_NO_STASH);
    CHECK(strcmp(garage_fault_code(m.fault), "E05") == 0);
    press(&m, KEY_RIGHT);
    CHECK(m.note == NOTE_BLOCKED);
}

static void test_get_from_empty_dock(void)
{
    garage_model_t m;
    char line[64];

    garage_model_init(&m);
    m.bay[GARAGE_DIR_DOCK] = BAY_EMPTY;
    CHECK(garage_get_block(&m) == BLOCK_READY);
    press(&m, KEY_RIGHT);
    press(&m, KEY_DOWN);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    CHECK(m.job == JOB_GET);
    CHECK(m.job_target == 1);
    CHECK(m.job_stash == -1);
    garage_model_step_line(&m, line, sizeof line);
    CHECK(strcmp(line, "旋转对准东北") == 0);
    CHECK(garage_model_bay_view(&m, GARAGE_DIR_DOCK) == BAY_EMPTY);

    while (m.prog < 28 && m.prog_phase == PROG_RUN) garage_model_job_tick(&m);
    garage_model_step_line(&m, line, sizeof line);
    CHECK(strcmp(line, "升降啮合") == 0);
    run_until_hold(&m);
    CHECK(m.bay[1] == BAY_EMPTY);
    CHECK(garage_dock(&m) == BAY_CAR);
    CHECK(m.bay[7] == BAY_EMPTY);
    CHECK(tray_units(&m) == 5);

    press(&m, KEY_RIGHT);
    CHECK(garage_dock(&m) == BAY_TRAY);
    CHECK(m.page == PAGE_MENU);
}

static void test_lists_skip_dock(void)
{
    garage_model_t m;
    int i;

    garage_model_init(&m);
    m.bay[GARAGE_DIR_DOCK] = BAY_CAR;
    CHECK(garage_get_block(&m) == BLOCK_DOCK_CAR);
    m.bay[GARAGE_DIR_DOCK] = BAY_EMPTY;
    press(&m, KEY_RIGHT);
    press(&m, KEY_DOWN);
    press(&m, KEY_RIGHT);
    CHECK(m.page == PAGE_GET);
    for (i = 0; i < m.get_n; i++) CHECK(m.get_map[i] != GARAGE_DIR_DOCK);
    press(&m, KEY_LEFT);
    press(&m, KEY_UP);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    CHECK(m.page == PAGE_PARK);
    for (i = 0; i < m.park_n; i++) CHECK(m.park_map[i] != GARAGE_DIR_DOCK);
}

static void test_idle_timeout_keeps_bays(void)
{
    garage_model_t m;
    bay_state_t before[GARAGE_BAY_COUNT];

    garage_model_init(&m);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    CHECK(m.page == PAGE_PARK);
    memcpy(before, m.bay, sizeof before);
    CHECK(garage_model_allow_idle_timeout(&m) == 1);
    garage_model_on_idle_timeout(&m);
    CHECK(m.page == PAGE_IDLE);
    CHECK(memcmp(m.bay, before, sizeof before) == 0);

    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    CHECK(m.page == PAGE_PROG);
    garage_model_on_idle_timeout(&m);
    CHECK(m.page == PAGE_PROG);
}

static void test_park_hold_auto_returns(void)
{
    garage_model_t m;
    int guard = 0;

    garage_model_init(&m);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    run_until_hold(&m);
    CHECK(m.prog_phase == PROG_HOLD);
    while (m.page == PAGE_PROG && guard < 20) {
        garage_model_job_tick(&m);
        guard++;
    }
    CHECK(m.page == PAGE_MENU);
    CHECK(m.job == JOB_NONE);
    CHECK(guard >= 8);
}

static void test_get_hold_does_not_auto_clear(void)
{
    garage_model_t m;
    int i;

    garage_model_init(&m);
    m.bay[GARAGE_DIR_DOCK] = BAY_EMPTY;
    press(&m, KEY_RIGHT);
    press(&m, KEY_DOWN);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    run_until_hold(&m);
    for (i = 0; i < 12; i++) garage_model_job_tick(&m);
    CHECK(m.page == PAGE_PROG);
    CHECK(garage_dock(&m) == BAY_CAR);
}

static void test_preset_does_not_eat_the_car(void)
{
    garage_model_t m;

    garage_model_init(&m);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    run_until_hold(&m);
    CHECK(m.bay[m.job_target] == BAY_CAR);
    CHECK(garage_dock(&m) != BAY_CAR);
    CHECK(m.bay[7] == BAY_CAR);
}

static void test_single_empty_clamps(void)
{
    garage_model_t m;
    int i;

    garage_model_init(&m);
    for (i = 0; i < GARAGE_BAY_COUNT; i++) m.bay[i] = BAY_CAR;
    m.bay[4] = BAY_EMPTY;
    m.bay[GARAGE_DIR_DOCK] = BAY_TRAY;
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    press(&m, KEY_RIGHT);
    CHECK(m.park_n == 1);
    CHECK(garage_model_focus_bay(&m) == 4);
    press(&m, KEY_UP);
    CHECK(m.note == NOTE_TOP);
    press(&m, KEY_DOWN);
    CHECK(m.note == NOTE_BOTTOM);
    CHECK(m.park_i == 0);
}

int main(void)
{
    test_seed_counts();
    test_dock_is_not_storage();
    test_menu_clamps();
    test_home_and_depart();
    test_demo_park_get_roundtrip();
    test_abort_restores();
    test_fetch_tray_when_dock_empty();
    test_fetch_creates_the_only_empty();
    test_faults_and_recovery();
    test_get_from_empty_dock();
    test_lists_skip_dock();
    test_idle_timeout_keeps_bays();
    test_park_hold_auto_returns();
    test_get_hold_does_not_auto_clear();
    test_preset_does_not_eat_the_car();
    test_single_empty_clamps();

    if (g_fails) {
        fprintf(stderr, "%d check(s) failed\n", g_fails);
        return 1;
    }
    printf("garage model ok\n");
    return 0;
}
