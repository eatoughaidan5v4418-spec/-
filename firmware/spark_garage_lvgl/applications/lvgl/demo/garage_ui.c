/*
 * Tower garage HMI - ORBIT deck
 * Idle: warm split time + bay ring (availability in the hole).
 * Keys open a full-width command deck; idle timeout returns.
 * Clock shows hours and minutes only.
 */

#include "garage_ui.h"

#include <lvgl.h>
#include <rtthread.h>
#include <rtdevice.h>
#include <board.h>
#include <string.h>
#include <time.h>

#define PIN_KEY_LEFT  GET_PIN(C, 0)
#define PIN_KEY_DOWN  GET_PIN(C, 1)
#define PIN_KEY_RIGHT GET_PIN(C, 4)
#define PIN_KEY_UP    GET_PIN(C, 5)

#define KEY_NONE 0
#define KEY_LEFT 1
#define KEY_RIGHT 2
#define KEY_UP 3
#define KEY_DOWN 4

#define BAY_COUNT 8
#define DIR_DOCK 6
#define IDLE_TIMEOUT_MS 15000
#define MENU_N 3

#define COL_BG    0x05070B
#define COL_INK   0xF3EFE4
#define COL_DIM   0x8B93A1
#define COL_AMBER 0xFFB020
#define COL_MINT  0x3DDC97
#define COL_BLUE  0x6AA4FF
#define COL_LINE  0x243044
#define COL_EMPTY 0x141A22
#define COL_CARD  0x10151C
#define COL_RED   0xFF4D4D

typedef enum { BAY_EMPTY = 0, BAY_TRAY = 1, BAY_CAR = 2 } bay_state_t;
typedef enum {
    PAGE_IDLE = 0, PAGE_MENU, PAGE_PARK, PAGE_GET, PAGE_PROG, PAGE_FAULT
} page_id_t;
typedef enum { JOB_IDLE = 0, JOB_PARK, JOB_GET } job_kind_t;

typedef struct {
    lv_obj_t *ring;
    lv_obj_t *pill[BAY_COUNT];
    lv_obj_t *name[BAY_COUNT];
    lv_obj_t *core_n;
    lv_obj_t *core_s;
    lv_coord_t cx;
    lv_coord_t cy;
} orbit_t;

static const char *const k_dir[BAY_COUNT] = {
    "E", "NE", "N", "NW", "W", "SW", "DK", "SE"
};
static const char *const k_week[7] = {
    "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"
};
/* offsets from orbit center, dock at the bottom */
static const lv_coord_t k_ox[BAY_COUNT] = { 58, 41, 0, -41, -58, -41, 0, 41 };
static const lv_coord_t k_oy[BAY_COUNT] = { 0, -41, -58, -41, 0, 41, 58, 41 };

static bay_state_t g_bay[BAY_COUNT] = {
    BAY_TRAY, BAY_CAR, BAY_TRAY, BAY_EMPTY,
    BAY_CAR, BAY_TRAY, BAY_TRAY, BAY_EMPTY
};

static page_id_t g_page = PAGE_IDLE;
static int g_menu = 0;
static int g_get_i = 0;
static int g_get_map[7];
static int g_get_n;
static job_kind_t g_job = JOB_IDLE;
static int g_job_t = -1;
static int g_prog = 0;
static char g_step[40];
static int g_h = 21, g_m = 6, g_s = 0, g_wday = 1, g_mon = 11, g_mday = 9;
static uint32_t g_last_in;
static int g_colon_on = 1;

static lv_obj_t *scr_idle, *scr_menu, *scr_park, *scr_get, *scr_prog, *scr_fault;
static lv_obj_t *lab_date, *lab_use, *lab_hh, *lab_mm, *colon_bar;
static orbit_t orb_idle, orb_park, orb_prog;
static lv_obj_t *menu_row[MENU_N], *menu_title[MENU_N], *menu_sub[MENU_N], *menu_val[MENU_N];
static lv_obj_t *park_body, *park_hint;
static lv_obj_t *get_item[7], *get_lab[7], *get_idx[7], *get_hint;
static lv_obj_t *prog_title, *prog_step;
static lv_obj_t *fault_code, *fault_body;
static lv_timer_t *job_timer;

static void refresh_idle(void);
static void refresh_menu(void);
static void refresh_get(void);
static void show_page(page_id_t id);

static void note_in(void) { g_last_in = lv_tick_get(); }

static int cars(void)
{
    int n = 0, i;
    for (i = 0; i < BAY_COUNT; i++) if (i != DIR_DOCK && g_bay[i] == BAY_CAR) n++;
    return n;
}
static int frees(void)
{
    int n = 0, i;
    for (i = 0; i < BAY_COUNT; i++) if (i != DIR_DOCK && g_bay[i] == BAY_EMPTY) n++;
    return n;
}
static int trays(void)
{
    int n = 0, i;
    for (i = 0; i < BAY_COUNT; i++) if (g_bay[i] == BAY_TRAY) n++;
    return n;
}
static int best_empty(void)
{
    static const int pref[] = { 7, 5, 0, 4, 1, 3, 2 };
    int i;
    for (i = 0; i < 7; i++) if (g_bay[pref[i]] == BAY_EMPTY) return pref[i];
    return -1;
}

static const char *dock_word(void)
{
    if (g_bay[DIR_DOCK] == BAY_CAR) return "CAR";
    if (g_bay[DIR_DOCK] == BAY_TRAY) return "TRAY";
    return "OPEN";
}

static void sync_rtc(void)
{
    time_t now = 0;
    struct tm *ti;
    if (rt_device_find("rtc")) now = time(RT_NULL);
    if (now > 100000 && (ti = localtime(&now))) {
        g_h = ti->tm_hour; g_m = ti->tm_min; g_s = ti->tm_sec;
        g_wday = ti->tm_wday; g_mon = ti->tm_mon + 1; g_mday = ti->tm_mday;
    }
}

static void tick_clk(void)
{
    g_s++;
    if (g_s >= 60) {
        g_s = 0; g_m++;
        if (g_m >= 60) {
            g_m = 0; g_h++;
            if (g_h >= 24) { g_h = 0; g_wday = (g_wday + 1) % 7; }
        }
    }
    g_colon_on ^= 1;
}

static void flat(lv_obj_t *o)
{
    lv_obj_set_style_pad_all(o, 0, 0);
    lv_obj_set_style_border_width(o, 0, 0);
    lv_obj_set_style_radius(o, 0, 0);
    lv_obj_set_style_shadow_width(o, 0, 0);
    lv_obj_clear_flag(o, LV_OBJ_FLAG_SCROLLABLE);
}

static lv_obj_t *screen(void)
{
    lv_obj_t *s = lv_obj_create(NULL);
    flat(s);
    lv_obj_set_style_bg_color(s, lv_color_hex(COL_BG), 0);
    lv_obj_set_style_bg_opa(s, LV_OPA_COVER, 0);
    return s;
}

static void opa_cb(void *obj, int32_t v)
{
    lv_obj_set_style_opa((lv_obj_t *)obj, (lv_opa_t)v, 0);
}

static void sweep_cb(void *obj, int32_t v)
{
    lv_arc_set_rotation((lv_obj_t *)obj, v);
}

static void orbit_build(lv_obj_t *par, orbit_t *o, lv_coord_t cx, lv_coord_t cy, int radar)
{
    int i;
    lv_obj_t *arc;

    o->cx = cx;
    o->cy = cy;

    arc = lv_arc_create(par);
    lv_obj_set_size(arc, 148, 148);
    lv_obj_set_pos(arc, cx - 74, cy - 74);
    lv_arc_set_rotation(arc, 270);
    lv_arc_set_bg_angles(arc, 0, 360);
    lv_arc_set_angles(arc, 0, radar ? 34 : 0);
    lv_arc_set_range(arc, 0, 100);
    lv_obj_remove_style(arc, NULL, LV_PART_KNOB);
    lv_obj_clear_flag(arc, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_arc_width(arc, 2, LV_PART_MAIN);
    lv_obj_set_style_arc_width(arc, 7, LV_PART_INDICATOR);
    lv_obj_set_style_arc_color(arc, lv_color_hex(COL_LINE), LV_PART_MAIN);
    lv_obj_set_style_arc_color(arc, lv_color_hex(COL_AMBER), LV_PART_INDICATOR);
    lv_obj_set_style_arc_rounded(arc, false, LV_PART_MAIN);
    lv_obj_set_style_arc_rounded(arc, false, LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(arc, LV_OPA_TRANSP, 0);
    o->ring = arc;

    if (radar) {
        lv_anim_t a;
        lv_anim_init(&a);
        lv_anim_set_var(&a, arc);
        lv_anim_set_exec_cb(&a, sweep_cb);
        lv_anim_set_values(&a, 0, 360);
        lv_anim_set_time(&a, 4200);
        lv_anim_set_repeat_count(&a, LV_ANIM_REPEAT_INFINITE);
        lv_anim_set_path_cb(&a, lv_anim_path_linear);
        lv_anim_start(&a);
    }

    for (i = 0; i < BAY_COUNT; i++) {
        lv_obj_t *p = lv_obj_create(par);
        lv_obj_t *n;
        flat(p);
        lv_obj_set_size(p, 40, 20);
        lv_obj_set_pos(p, cx + k_ox[i] - 20, cy + k_oy[i] - 10);
        lv_obj_set_style_radius(p, 10, 0);
        lv_obj_set_style_bg_opa(p, LV_OPA_COVER, 0);
        n = lv_label_create(p);
        lv_obj_set_style_text_font(n, &lv_font_montserrat_12, 0);
        lv_label_set_text(n, k_dir[i]);
        lv_obj_center(n);
        o->pill[i] = p;
        o->name[i] = n;
    }

    o->core_n = lv_label_create(par);
    lv_obj_set_style_text_font(o->core_n, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(o->core_n, lv_color_hex(COL_INK), 0);
    lv_obj_set_pos(o->core_n, cx - 24, cy - 22);
    lv_obj_set_width(o->core_n, 48);
    lv_obj_set_style_text_align(o->core_n, LV_TEXT_ALIGN_CENTER, 0);

    o->core_s = lv_label_create(par);
    lv_obj_set_style_text_font(o->core_s, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(o->core_s, lv_color_hex(COL_AMBER), 0);
    lv_obj_set_pos(o->core_s, cx - 28, cy + 6);
    lv_obj_set_width(o->core_s, 56);
    lv_obj_set_style_text_align(o->core_s, LV_TEXT_ALIGN_CENTER, 0);
}

static void orbit_paint(orbit_t *o, int hot, const char *hero, const char *cap)
{
    int i;
    for (i = 0; i < BAY_COUNT; i++) {
        uint32_t bg = COL_EMPTY;
        uint32_t fg = 0x5C6774;
        int border = 0;
        uint32_t bc = COL_LINE;

        if (g_bay[i] == BAY_CAR) { bg = 0x0E2C22; fg = COL_MINT; }
        else if (g_bay[i] == BAY_TRAY) { bg = 0x10243C; fg = COL_BLUE; }

        if (i == hot) {
            bg = COL_AMBER;
            fg = 0x1A1204;
            border = 0;
        } else if (i == DIR_DOCK) {
            border = 2;
            bc = COL_AMBER;
        }

        lv_obj_set_style_bg_color(o->pill[i], lv_color_hex(bg), 0);
        lv_obj_set_style_text_color(o->name[i], lv_color_hex(fg), 0);
        lv_obj_set_style_border_width(o->pill[i], border, 0);
        lv_obj_set_style_border_color(o->pill[i], lv_color_hex(bc), 0);
        if (i == DIR_DOCK && hot != DIR_DOCK)
            lv_label_set_text(o->name[i], dock_word());
        else
            lv_label_set_text(o->name[i], k_dir[i]);
    }
    lv_label_set_text(o->core_n, hero);
    lv_label_set_text(o->core_s, cap);
}

static void orbit_progress(orbit_t *o, int pct)
{
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    lv_arc_set_rotation(o->ring, 270);
    lv_arc_set_angles(o->ring, 0, (uint16_t)(pct * 360 / 100));
}

static void show_page(page_id_t id)
{
    g_page = id;
    switch (id) {
    case PAGE_IDLE:
        refresh_idle();
        lv_scr_load_anim(scr_idle, LV_SCR_LOAD_ANIM_FADE_ON, 180, 0, false);
        break;
    case PAGE_MENU:
        refresh_menu();
        lv_scr_load_anim(scr_menu, LV_SCR_LOAD_ANIM_MOVE_TOP, 220, 0, false);
        break;
    case PAGE_PARK:
        lv_scr_load_anim(scr_park, LV_SCR_LOAD_ANIM_MOVE_LEFT, 200, 0, false);
        break;
    case PAGE_GET:
        refresh_get();
        lv_scr_load_anim(scr_get, LV_SCR_LOAD_ANIM_MOVE_LEFT, 200, 0, false);
        break;
    case PAGE_PROG:
        lv_scr_load_anim(scr_prog, LV_SCR_LOAD_ANIM_FADE_ON, 140, 0, false);
        break;
    case PAGE_FAULT:
        lv_scr_load_anim(scr_fault, LV_SCR_LOAD_ANIM_FADE_ON, 140, 0, false);
        break;
    }
}

static void go_idle(void)
{
    g_menu = 0;
    show_page(PAGE_IDLE);
}

static void refresh_idle(void)
{
    char hero[8];
    lv_label_set_text_fmt(lab_hh, "%02d", g_h);
    lv_label_set_text_fmt(lab_mm, "%02d", g_m);
    lv_obj_set_style_bg_opa(colon_bar, g_colon_on ? LV_OPA_COVER : LV_OPA_20, 0);
    lv_label_set_text_fmt(lab_date, "%s  %02d-%02d", k_week[g_wday], g_mon, g_mday);
    lv_label_set_text_fmt(lab_use, "USE %02d", cars());
    rt_snprintf(hero, sizeof(hero), "%02d", frees());
    orbit_paint(&orb_idle, -1, hero, "FREE");
}

static void style_plate(int i, int on)
{
    lv_obj_set_style_bg_color(menu_row[i],
        lv_color_hex(on ? COL_AMBER : COL_CARD), 0);
    lv_obj_set_style_border_color(menu_row[i],
        lv_color_hex(on ? COL_AMBER : COL_LINE), 0);
    lv_obj_set_style_text_color(menu_title[i],
        lv_color_hex(on ? 0x1A1204 : COL_INK), 0);
    lv_obj_set_style_text_color(menu_sub[i],
        lv_color_hex(on ? 0x5C4310 : COL_DIM), 0);
    lv_obj_set_style_text_color(menu_val[i],
        lv_color_hex(on ? 0x1A1204 : COL_AMBER), 0);
}

static void refresh_menu(void)
{
    int i;
    lv_label_set_text_fmt(menu_sub[0], "EMPTY %d   TRAY %d", frees(), trays());
    lv_label_set_text_fmt(menu_val[0], "%02d", frees());
    lv_label_set_text_fmt(menu_sub[1], "CARS ON TOWER");
    lv_label_set_text_fmt(menu_val[1], "%02d", cars());
    lv_label_set_text_fmt(menu_sub[2], "DOCK %s", dock_word());
    lv_label_set_text(menu_val[2], "<-");
    for (i = 0; i < MENU_N; i++) style_plate(i, i == g_menu);
}

static void rebuild_get(void)
{
    int i, n = 0;
    for (i = 0; i < BAY_COUNT; i++) {
        if (i == DIR_DOCK) continue;
        if (g_bay[i] == BAY_CAR && n < 7) {
            g_get_map[n] = i;
            lv_obj_clear_flag(get_item[n], LV_OBJ_FLAG_HIDDEN);
            lv_label_set_text_fmt(get_lab[n], "BAY  %s", k_dir[i]);
            lv_label_set_text_fmt(get_idx[n], "%d", n + 1);
            n++;
        }
    }
    g_get_n = n;
    while (n < 7) {
        lv_obj_add_flag(get_item[n], LV_OBJ_FLAG_HIDDEN);
        n++;
    }
    if (g_get_i >= g_get_n) g_get_i = 0;
}

static void refresh_get(void)
{
    int i;
    rebuild_get();
    for (i = 0; i < g_get_n; i++) {
        int on = (i == g_get_i);
        lv_obj_align(get_item[i], LV_ALIGN_TOP_MID, 0, 40 + i * 26);
        lv_obj_set_style_bg_color(get_item[i],
            lv_color_hex(on ? COL_AMBER : COL_CARD), 0);
        lv_obj_set_style_text_color(get_lab[i],
            lv_color_hex(on ? 0x1A1204 : COL_INK), 0);
        lv_obj_set_style_text_color(get_idx[i],
            lv_color_hex(on ? 0x1A1204 : COL_AMBER), 0);
    }
    lv_label_set_text_fmt(get_hint, "%d/%d", g_get_n ? g_get_i + 1 : 0, g_get_n);
}

static void refresh_prog(void)
{
    char hero[8];
    lv_label_set_text(prog_title, g_job == JOB_PARK ? "PARKING" : "RECALL");
    lv_label_set_text(prog_step, g_step);
    rt_snprintf(hero, sizeof(hero), "%d", g_prog);
    orbit_progress(&orb_prog, g_prog);
    orbit_paint(&orb_prog, g_job_t, hero, "PCT");
}

static void raise_fault(const char *code, const char *msg)
{
    g_job = JOB_IDLE;
    if (job_timer) lv_timer_pause(job_timer);
    lv_label_set_text(fault_code, code);
    lv_label_set_text(fault_body, msg);
    note_in();
    show_page(PAGE_FAULT);
}

static void job_cb(lv_timer_t *t)
{
    (void)t;
    if (g_job == JOB_IDLE) return;
    note_in();
    g_prog += 4;
    if (g_prog > 100) g_prog = 100;
    if (g_job == JOB_PARK) {
        if (g_prog < 28) rt_snprintf(g_step, sizeof(g_step), "ROTATE  DOCK");
        else if (g_prog < 58) rt_snprintf(g_step, sizeof(g_step), "LOAD  VEHICLE");
        else if (g_prog < 86) rt_snprintf(g_step, sizeof(g_step), "MOVE  %s", k_dir[g_job_t]);
        else rt_snprintf(g_step, sizeof(g_step), "SEAT  +  PRESET");
    } else {
        if (g_prog < 30) rt_snprintf(g_step, sizeof(g_step), "CLEAR  DOCK");
        else if (g_prog < 72) rt_snprintf(g_step, sizeof(g_step), "PICK  %s", k_dir[g_job_t]);
        else rt_snprintf(g_step, sizeof(g_step), "DELIVER  DOCK");
    }
    refresh_prog();
    if (g_prog >= 100) {
        if (g_job == JOB_PARK) {
            int i;
            g_bay[DIR_DOCK] = BAY_EMPTY;
            g_bay[g_job_t] = BAY_CAR;
            for (i = 0; i < BAY_COUNT; i++) {
                if (i != DIR_DOCK && g_bay[i] == BAY_TRAY) {
                    g_bay[i] = BAY_EMPTY;
                    g_bay[DIR_DOCK] = BAY_TRAY;
                    break;
                }
            }
        } else {
            g_bay[g_job_t] = BAY_EMPTY;
            g_bay[DIR_DOCK] = BAY_CAR;
        }
        g_job = JOB_IDLE;
        lv_timer_pause(job_timer);
        note_in();
        show_page(PAGE_MENU);
    }
}

static void start_job(job_kind_t job, int target)
{
    g_job = job;
    g_job_t = target;
    g_prog = 0;
    rt_snprintf(g_step, sizeof(g_step), "ARMING");
    refresh_prog();
    note_in();
    show_page(PAGE_PROG);
    lv_timer_resume(job_timer);
    lv_timer_reset(job_timer);
}

static void menu_ok(void)
{
    if (g_menu == 0) {
        int i, found = -1, t;
        char hero[8];
        if (frees() <= 0) { raise_fault("E01", "NO EMPTY BAY"); return; }
        if (g_bay[DIR_DOCK] == BAY_CAR) { raise_fault("E02", "DOCK IS BUSY"); return; }
        if (g_bay[DIR_DOCK] != BAY_TRAY) {
            for (i = 0; i < BAY_COUNT; i++)
                if (i != DIR_DOCK && g_bay[i] == BAY_TRAY) { found = i; break; }
            if (found < 0) { raise_fault("E03", "NO TRAY LEFT"); return; }
            g_bay[found] = BAY_EMPTY;
            g_bay[DIR_DOCK] = BAY_TRAY;
        }
        t = best_empty();
        lv_label_set_text(park_body, "TRAY IS ON THE DOCK");
        rt_snprintf(hero, sizeof(hero), "%s", t >= 0 ? k_dir[t] : "--");
        orbit_paint(&orb_park, t, hero, "SLOT");
        note_in();
        show_page(PAGE_PARK);
    } else if (g_menu == 1) {
        rebuild_get();
        if (g_get_n <= 0) { raise_fault("E04", "NO CAR STORED"); return; }
        g_get_i = 0;
        note_in();
        show_page(PAGE_GET);
    } else {
        go_idle();
    }
}

static void on_key(uint8_t key)
{
    note_in();
    if (g_page == PAGE_IDLE) { g_menu = 0; show_page(PAGE_MENU); return; }

    if (g_page == PAGE_MENU) {
        if (key == KEY_UP) g_menu = (g_menu + MENU_N - 1) % MENU_N;
        else if (key == KEY_DOWN) g_menu = (g_menu + 1) % MENU_N;
        else if (key == KEY_RIGHT) { menu_ok(); return; }
        else if (key == KEY_LEFT) { go_idle(); return; }
        refresh_menu();
    } else if (g_page == PAGE_PARK) {
        if (key == KEY_LEFT) show_page(PAGE_MENU);
        else if (key == KEY_RIGHT) {
            int t = best_empty();
            if (t < 0) { raise_fault("E01", "NO EMPTY BAY"); return; }
            g_bay[DIR_DOCK] = BAY_CAR;
            start_job(JOB_PARK, t);
        }
    } else if (g_page == PAGE_GET) {
        if (key == KEY_LEFT) show_page(PAGE_MENU);
        else if (key == KEY_UP && g_get_n) g_get_i = (g_get_i + g_get_n - 1) % g_get_n;
        else if (key == KEY_DOWN && g_get_n) g_get_i = (g_get_i + 1) % g_get_n;
        else if (key == KEY_RIGHT && g_get_n) start_job(JOB_GET, g_get_map[g_get_i]);
        refresh_get();
    } else if (g_page == PAGE_PROG) {
        if (key == KEY_LEFT) {
            g_job = JOB_IDLE;
            lv_timer_pause(job_timer);
            show_page(PAGE_MENU);
        }
    } else if (g_page == PAGE_FAULT) {
        show_page(PAGE_MENU);
    }
}

static uint8_t key_read(void)
{
    if (rt_pin_read(PIN_KEY_LEFT) == PIN_LOW) return KEY_LEFT;
    if (rt_pin_read(PIN_KEY_RIGHT) == PIN_LOW) return KEY_RIGHT;
    if (rt_pin_read(PIN_KEY_UP) == PIN_LOW) return KEY_UP;
    if (rt_pin_read(PIN_KEY_DOWN) == PIN_LOW) return KEY_DOWN;
    return KEY_NONE;
}

static void key_cb(lv_timer_t *t)
{
    static uint8_t last = KEY_NONE;
    uint8_t k = key_read();
    (void)t;
    if (k != KEY_NONE && k != last) on_key(k);
    last = k;
    if (g_page != PAGE_IDLE && g_job == JOB_IDLE &&
        lv_tick_elaps(g_last_in) >= IDLE_TIMEOUT_MS)
        go_idle();
}

static void clk_cb(lv_timer_t *t)
{
    (void)t;
    tick_clk();
    if (g_page == PAGE_IDLE) refresh_idle();
}

static void build_idle(void)
{
    scr_idle = screen();

    lab_date = lv_label_create(scr_idle);
    lv_obj_set_style_text_font(lab_date, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(lab_date, lv_color_hex(COL_DIM), 0);
    lv_obj_align(lab_date, LV_ALIGN_TOP_LEFT, 12, 6);

    lab_use = lv_label_create(scr_idle);
    lv_obj_set_style_text_font(lab_use, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(lab_use, lv_color_hex(COL_MINT), 0);
    lv_obj_align(lab_use, LV_ALIGN_TOP_RIGHT, -12, 6);

    {
        lv_obj_t *row = lv_obj_create(scr_idle);
        flat(row);
        lv_obj_set_size(row, 224, 54);
        lv_obj_align(row, LV_ALIGN_TOP_MID, 0, 24);
        lv_obj_set_style_bg_opa(row, LV_OPA_TRANSP, 0);

        lab_hh = lv_label_create(row);
        lv_obj_set_style_text_font(lab_hh, &lv_font_montserrat_48, 0);
        lv_obj_set_style_text_color(lab_hh, lv_color_hex(COL_INK), 0);
        lv_obj_align(lab_hh, LV_ALIGN_CENTER, -52, 0);

        lab_mm = lv_label_create(row);
        lv_obj_set_style_text_font(lab_mm, &lv_font_montserrat_48, 0);
        lv_obj_set_style_text_color(lab_mm, lv_color_hex(COL_INK), 0);
        lv_obj_align(lab_mm, LV_ALIGN_CENTER, 52, 0);

        colon_bar = lv_obj_create(row);
        flat(colon_bar);
        lv_obj_set_size(colon_bar, 4, 28);
        lv_obj_set_style_radius(colon_bar, 2, 0);
        lv_obj_set_style_bg_color(colon_bar, lv_color_hex(COL_AMBER), 0);
        lv_obj_set_style_bg_opa(colon_bar, LV_OPA_COVER, 0);
        lv_obj_align(colon_bar, LV_ALIGN_CENTER, 0, 0);
    }

    orbit_build(scr_idle, &orb_idle, 120, 168, 1);
}

static void build_menu(void)
{
    static const char *titles[MENU_N] = { "PARK", "GET", "HOME" };
    int i;

    scr_menu = screen();

    for (i = 0; i < MENU_N; i++) {
        lv_obj_t *row = lv_obj_create(scr_menu);
        lv_obj_t *title, *sub, *val;
        flat(row);
        lv_obj_set_size(row, 224, 70);
        lv_obj_set_pos(row, 8, 8 + i * 78);
        lv_obj_set_style_radius(row, 14, 0);
        lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
        lv_obj_set_style_border_width(row, 2, 0);

        title = lv_label_create(row);
        lv_obj_set_style_text_font(title, &lv_font_montserrat_28, 0);
        lv_label_set_text(title, titles[i]);
        lv_obj_align(title, LV_ALIGN_LEFT_MID, 16, -10);

        sub = lv_label_create(row);
        lv_obj_set_style_text_font(sub, &lv_font_montserrat_12, 0);
        lv_label_set_text(sub, "");
        lv_obj_align(sub, LV_ALIGN_LEFT_MID, 16, 16);

        val = lv_label_create(row);
        lv_obj_set_style_text_font(val, &lv_font_montserrat_28, 0);
        lv_label_set_text(val, "00");
        lv_obj_align(val, LV_ALIGN_RIGHT_MID, -16, 0);

        menu_row[i] = row;
        menu_title[i] = title;
        menu_sub[i] = sub;
        menu_val[i] = val;
    }
}

static void build_park(void)
{
    lv_obj_t *t;
    scr_park = screen();

    t = lv_label_create(scr_park);
    lv_obj_set_style_text_font(t, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(t, lv_color_hex(COL_AMBER), 0);
    lv_label_set_text(t, "PARK");
    lv_obj_align(t, LV_ALIGN_TOP_LEFT, 14, 8);

    park_body = lv_label_create(scr_park);
    lv_obj_set_style_text_font(park_body, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(park_body, lv_color_hex(COL_INK), 0);
    lv_obj_align(park_body, LV_ALIGN_TOP_RIGHT, -12, 8);

    orbit_build(scr_park, &orb_park, 120, 132, 0);

    park_hint = lv_label_create(scr_park);
    lv_obj_set_style_text_font(park_hint, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(park_hint, lv_color_hex(COL_DIM), 0);
    lv_label_set_text(park_hint, "RIGHT  CONFIRM     LEFT  BACK");
    lv_obj_align(park_hint, LV_ALIGN_BOTTOM_MID, 0, -8);
}

static void build_get(void)
{
    int i;
    lv_obj_t *t;
    scr_get = screen();

    t = lv_label_create(scr_get);
    lv_obj_set_style_text_font(t, &lv_font_montserrat_20, 0);
    lv_obj_set_style_text_color(t, lv_color_hex(COL_INK), 0);
    lv_label_set_text(t, "RECALL");
    lv_obj_align(t, LV_ALIGN_TOP_LEFT, 12, 8);

    get_hint = lv_label_create(scr_get);
    lv_obj_set_style_text_font(get_hint, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(get_hint, lv_color_hex(COL_AMBER), 0);
    lv_obj_align(get_hint, LV_ALIGN_TOP_RIGHT, -12, 12);

    for (i = 0; i < 7; i++) {
        lv_obj_t *row = lv_obj_create(scr_get);
        lv_obj_t *idx, *lab;
        flat(row);
        lv_obj_set_size(row, 216, 24);
        lv_obj_set_style_radius(row, 8, 0);
        lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
        lv_obj_set_style_border_width(row, 0, 0);

        idx = lv_label_create(row);
        lv_obj_set_style_text_font(idx, &lv_font_montserrat_12, 0);
        lv_obj_align(idx, LV_ALIGN_LEFT_MID, 10, 0);

        lab = lv_label_create(row);
        lv_obj_set_style_text_font(lab, &lv_font_montserrat_14, 0);
        lv_obj_align(lab, LV_ALIGN_LEFT_MID, 32, 0);

        get_item[i] = row;
        get_idx[i] = idx;
        get_lab[i] = lab;
        lv_obj_add_flag(row, LV_OBJ_FLAG_HIDDEN);
    }
}

static void build_prog(void)
{
    scr_prog = screen();

    prog_title = lv_label_create(scr_prog);
    lv_obj_set_style_text_font(prog_title, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(prog_title, lv_color_hex(COL_AMBER), 0);
    lv_obj_align(prog_title, LV_ALIGN_TOP_LEFT, 14, 8);

    prog_step = lv_label_create(scr_prog);
    lv_obj_set_style_text_font(prog_step, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(prog_step, lv_color_hex(COL_INK), 0);
    lv_obj_align(prog_step, LV_ALIGN_TOP_RIGHT, -12, 8);

    orbit_build(scr_prog, &orb_prog, 120, 136, 0);

    {
        lv_obj_t *h = lv_label_create(scr_prog);
        lv_obj_set_style_text_font(h, &lv_font_montserrat_12, 0);
        lv_obj_set_style_text_color(h, lv_color_hex(COL_DIM), 0);
        lv_label_set_text(h, "LEFT  ABORT");
        lv_obj_align(h, LV_ALIGN_BOTTOM_MID, 0, -8);
    }
}

static void build_fault(void)
{
    lv_obj_t *bar, *t;
    scr_fault = screen();

    bar = lv_obj_create(scr_fault);
    flat(bar);
    lv_obj_set_size(bar, 240, 6);
    lv_obj_set_style_bg_color(bar, lv_color_hex(COL_RED), 0);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, 0);
    lv_obj_align(bar, LV_ALIGN_TOP_MID, 0, 0);

    t = lv_label_create(scr_fault);
    lv_obj_set_style_text_font(t, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(t, lv_color_hex(COL_RED), 0);
    lv_label_set_text(t, "HOLD");
    lv_obj_align(t, LV_ALIGN_TOP_MID, 0, 28);

    fault_code = lv_label_create(scr_fault);
    lv_obj_set_style_text_font(fault_code, &lv_font_montserrat_48, 0);
    lv_obj_set_style_text_color(fault_code, lv_color_hex(COL_INK), 0);
    lv_obj_align(fault_code, LV_ALIGN_CENTER, 0, -16);

    fault_body = lv_label_create(scr_fault);
    lv_obj_set_style_text_font(fault_body, &lv_font_montserrat_16, 0);
    lv_obj_set_style_text_color(fault_body, lv_color_hex(COL_DIM), 0);
    lv_obj_align(fault_body, LV_ALIGN_CENTER, 0, 28);

    t = lv_label_create(scr_fault);
    lv_obj_set_style_text_font(t, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(t, lv_color_hex(COL_AMBER), 0);
    lv_label_set_text(t, "ANY KEY  RETURNS");
    lv_obj_align(t, LV_ALIGN_BOTTOM_MID, 0, -18);
}

void garage_ui_init(void)
{
    rt_pin_mode(PIN_KEY_LEFT, PIN_MODE_INPUT_PULLUP);
    rt_pin_mode(PIN_KEY_RIGHT, PIN_MODE_INPUT_PULLUP);
    rt_pin_mode(PIN_KEY_UP, PIN_MODE_INPUT_PULLUP);
    rt_pin_mode(PIN_KEY_DOWN, PIN_MODE_INPUT_PULLUP);

    build_idle();
    build_menu();
    build_park();
    build_get();
    build_prog();
    build_fault();

    sync_rtc();
    note_in();
    refresh_idle();
    refresh_menu();
    lv_scr_load(scr_idle);
    g_page = PAGE_IDLE;

    job_timer = lv_timer_create(job_cb, 140, NULL);
    lv_timer_pause(job_timer);
    lv_timer_create(key_cb, 30, NULL);
    lv_timer_create(clk_cb, 1000, NULL);

    rt_kprintf("[garage_ui] orbit deck ready\n");
}
