/*
 * 星火1号塔式车库 HMI，240x240，无触摸。
 * 按键在本文件里轮询（左 PC0 / 下 PC1 / 右 PC4 / 上 PC5，低电平）。
 * 车位规则在 garage_model.c。这里只负责把状态画出来，不阻塞 LVGL。
 */

#include "garage_ui.h"
#include "garage_model.h"

#include <lvgl.h>
#include <rtthread.h>
#include <rtdevice.h>
#include <board.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

extern const lv_font_t font_garage_16;
extern const lv_font_t font_garage_20;

#define PIN_KEY_LEFT  GET_PIN(C, 0)
#define PIN_KEY_DOWN  GET_PIN(C, 1)
#define PIN_KEY_RIGHT GET_PIN(C, 4)
#define PIN_KEY_UP    GET_PIN(C, 5)

#define IDLE_TIMEOUT_MS 15000
#define NOTE_MS 700

#define COL_BG     0x07090E
#define COL_CARD   0x121820
#define COL_INK    0xF4F1E8
#define COL_DIM    0x8E97A6
#define COL_AMBER  0xFFB020
#define COL_MINT   0x3DDC97
#define COL_BLUE   0x6AA4FF
#define COL_LINE   0x2C384C
#define COL_RED    0xFF5A5A
#define COL_WARN   0xFF8A4A
#define COL_ON     0x1A1204
#define COL_ON_DIM 0x5C4310
#define COL_TRAY   0x1B4F86
#define COL_CAR    0x0F8A5B
#define COL_EMPTY  0x1A212C

#define IDLE_CX 120
#define IDLE_CY 158
#define IDLE_R  40
#define WORK_CX 120
#define WORK_CY 102
#define WORK_R  40
#define PROG_CX 120
#define PROG_CY 128
#define PROG_R  42

typedef struct {
    lv_obj_t *ring;
    lv_obj_t *pill[GARAGE_BAY_COUNT];
    lv_obj_t *name[GARAGE_BAY_COUNT];
    lv_obj_t *core_n;
    lv_obj_t *core_s;
    lv_coord_t cx;
    lv_coord_t cy;
} orbit_t;

static garage_model_t g;
static uint32_t g_last_in;
static int g_h = 21, g_m = 6, g_s = 0, g_wday = 1, g_mon = 11, g_mday = 9;
static int g_colon_on = 1;
static garage_note_t s_note = NOTE_NONE;
static uint32_t s_note_t;
static lv_timer_t *job_timer;

static lv_obj_t *scr_idle, *scr_menu, *scr_park, *scr_get, *scr_prog, *scr_fault;
static lv_obj_t *lab_date, *lab_use, *lab_hh, *lab_mm, *colon_bar;
static lv_obj_t *leg_lab[4];
static orbit_t orb_idle, orb_park, orb_prog;
static lv_obj_t *menu_row[GARAGE_MENU_N];
static lv_obj_t *menu_accent[GARAGE_MENU_N];
static lv_obj_t *menu_title[GARAGE_MENU_N];
static lv_obj_t *menu_sub[GARAGE_MENU_N];
static lv_obj_t *menu_val[GARAGE_MENU_N];
static lv_obj_t *menu_hint;
static lv_obj_t *park_phase, *park_l1, *park_l2, *park_hint;
static lv_obj_t *get_count, *get_sub, *get_hint;
static lv_obj_t *get_row[GARAGE_STORE_N], *get_idx[GARAGE_STORE_N];
static lv_obj_t *get_name[GARAGE_STORE_N], *get_tag[GARAGE_STORE_N];
static lv_obj_t *prog_title, *prog_frac, *prog_step, *prog_hint;
static lv_obj_t *fault_code, *fault_title, *fault_body, *fault_action, *fault_hint;

static const char *const k_week[7] = {
    "周日", "周一", "周二", "周三", "周四", "周五", "周六"
};
static const uint32_t k_accent[GARAGE_MENU_N] = { COL_AMBER, COL_MINT, 0x3A4558 };

static void apply_page(int animate);
static void refresh_idle(void);
static void refresh_menu(void);
static void refresh_park(void);
static void refresh_get(void);
static void refresh_prog(void);
static void refresh_fault(void);

static void note_in(void)
{
    g_last_in = lv_tick_get();
}

static void capture_note(void)
{
    if (g.note != NOTE_NONE) {
        s_note = g.note;
        s_note_t = lv_tick_get();
    } else {
        s_note = NOTE_NONE;
    }
}

static garage_note_t live_note(void)
{
    if (s_note != NOTE_NONE && lv_tick_elaps(s_note_t) < NOTE_MS) return s_note;
    return NOTE_NONE;
}

static const char *hint_for(garage_note_t note, const char *normal)
{
    if (note == NOTE_TOP) return "到顶";
    if (note == NOTE_BOTTOM) return "到底";
    if (note == NOTE_BUSY) return "作业中";
    if (note == NOTE_BLOCKED) return "无效";
    return normal;
}

static void paint_hint(lv_obj_t *lab, const char *normal)
{
    garage_note_t note = live_note();

    lv_label_set_text(lab, hint_for(note, normal));
    lv_obj_set_style_text_color(lab,
        lv_color_hex(note == NOTE_NONE ? COL_DIM : COL_AMBER), 0);
}

static void sync_rtc(void)
{
    time_t now = 0;
    struct tm *ti;

    if (rt_device_find("rtc")) now = time(RT_NULL);
    if (now > 100000 && (ti = localtime(&now))) {
        g_h = ti->tm_hour;
        g_m = ti->tm_min;
        g_s = ti->tm_sec;
        g_wday = ti->tm_wday;
        g_mon = ti->tm_mon + 1;
        g_mday = ti->tm_mday;
    }
}

static void tick_clk(void)
{
    g_s++;
    if (g_s < 60) {
        g_colon_on ^= 1;
        return;
    }
    g_s = 0;
    g_m++;
    if (g_m >= 60) {
        g_m = 0;
        g_h++;
        if (g_h >= 24) {
            g_h = 0;
            g_wday = (g_wday + 1) % 7;
        }
    }
    g_colon_on ^= 1;
    sync_rtc();
}

static void flat(lv_obj_t *obj)
{
    lv_obj_set_style_pad_all(obj, 0, 0);
    lv_obj_set_style_border_width(obj, 0, 0);
    lv_obj_set_style_radius(obj, 0, 0);
    lv_obj_set_style_shadow_width(obj, 0, 0);
    lv_obj_clear_flag(obj, LV_OBJ_FLAG_SCROLLABLE);
}

static lv_obj_t *make_screen(uint32_t bar_color)
{
    lv_obj_t *scr = lv_obj_create(NULL);
    lv_obj_t *bar;

    flat(scr);
    lv_obj_set_style_bg_color(scr, lv_color_hex(COL_BG), 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);

    bar = lv_obj_create(scr);
    flat(bar);
    lv_obj_set_size(bar, 240, 3);
    lv_obj_set_style_bg_color(bar, lv_color_hex(bar_color), 0);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, 0);
    lv_obj_align(bar, LV_ALIGN_TOP_MID, 0, 0);
    return scr;
}

static lv_obj_t *mk_label(lv_obj_t *parent, const lv_font_t *font, uint32_t color, const char *text)
{
    lv_obj_t *lab = lv_label_create(parent);

    lv_obj_set_style_text_font(lab, font, 0);
    lv_obj_set_style_text_color(lab, lv_color_hex(color), 0);
    lv_label_set_text(lab, text);
    return lab;
}

static lv_obj_t *mk_footer(lv_obj_t *parent)
{
    lv_obj_t *lab = mk_label(parent, &font_garage_16, COL_DIM, "");

    lv_obj_set_width(lab, 228);
    lv_obj_set_style_text_align(lab, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lab, LV_ALIGN_BOTTOM_MID, 0, -4);
    return lab;
}

static void bay_offset(int index, int radius, lv_coord_t *x, lv_coord_t *y)
{
    /* 0° is east. Screen +y is south, so the dock sits at the bottom. */
    static const int8_t cs[GARAGE_BAY_COUNT] = { 100, 71, 0, -71, -100, -71, 0, 71 };
    static const int8_t sn[GARAGE_BAY_COUNT] = { 0, -71, -100, -71, 0, 71, 100, 71 };

    *x = (lv_coord_t)((int)cs[index] * radius / 100);
    *y = (lv_coord_t)((int)sn[index] * radius / 100);
}

static void sweep_cb(void *obj, int32_t value)
{
    lv_arc_set_rotation((lv_obj_t *)obj, value);
}

static int radar_on;

static void orbit_build(lv_obj_t *parent, orbit_t *orbit, lv_coord_t cx, lv_coord_t cy, int radius)
{
    int arc_r = radius + 14;
    int i;
    lv_obj_t *arc;

    orbit->cx = cx;
    orbit->cy = cy;

    arc = lv_arc_create(parent);
    lv_obj_set_size(arc, arc_r * 2, arc_r * 2);
    lv_obj_set_pos(arc, cx - arc_r, cy - arc_r);
    lv_arc_set_rotation(arc, 270);
    lv_arc_set_bg_angles(arc, 0, 360);
    lv_arc_set_angles(arc, 0, 0);
    lv_obj_remove_style(arc, NULL, LV_PART_KNOB);
    lv_obj_clear_flag(arc, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_arc_width(arc, 2, LV_PART_MAIN);
    lv_obj_set_style_arc_width(arc, 6, LV_PART_INDICATOR);
    lv_obj_set_style_arc_color(arc, lv_color_hex(COL_LINE), LV_PART_MAIN);
    lv_obj_set_style_arc_color(arc, lv_color_hex(COL_AMBER), LV_PART_INDICATOR);
    lv_obj_set_style_arc_rounded(arc, false, LV_PART_MAIN);
    lv_obj_set_style_arc_rounded(arc, false, LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(arc, LV_OPA_TRANSP, 0);
    orbit->ring = arc;

    for (i = 0; i < GARAGE_BAY_COUNT; i++) {
        lv_coord_t x;
        lv_coord_t y;
        lv_obj_t *pill;
        lv_obj_t *name;

        bay_offset(i, radius, &x, &y);
        pill = lv_obj_create(parent);
        flat(pill);
        lv_obj_set_size(pill, 34, 18);
        lv_obj_set_pos(pill, cx + x - 17, cy + y - 9);
        lv_obj_set_style_radius(pill, i == GARAGE_DIR_DOCK ? 4 : 9, 0);
        lv_obj_set_style_bg_opa(pill, LV_OPA_COVER, 0);
        name = mk_label(pill, &lv_font_montserrat_12, COL_DIM, garage_bay_short(i));
        lv_obj_center(name);
        orbit->pill[i] = pill;
        orbit->name[i] = name;
    }

    orbit->core_n = mk_label(parent, &lv_font_montserrat_28, COL_INK, "00");
    lv_obj_set_width(orbit->core_n, 72);
    lv_obj_set_style_text_align(orbit->core_n, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_pos(orbit->core_n, cx - 36, cy - 24);

    orbit->core_s = mk_label(parent, &font_garage_16, COL_AMBER, "");
    lv_obj_set_width(orbit->core_s, 72);
    lv_obj_set_style_text_align(orbit->core_s, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_pos(orbit->core_s, cx - 36, cy + 6);
}

static void orbit_paint(orbit_t *orbit, int hot, const char *hero, const char *cap)
{
    int i;

    for (i = 0; i < GARAGE_BAY_COUNT; i++) {
        bay_state_t state = garage_model_bay_view(&g, i);
        uint32_t bg = COL_EMPTY;
        uint32_t fg = 0x8B95A3;
        int border = 1;
        uint32_t border_c = COL_LINE;

        if (state == BAY_CAR) {
            bg = COL_CAR;
            fg = 0xF4FFF9;
            border = 0;
        } else if (state == BAY_TRAY) {
            bg = COL_TRAY;
            fg = 0xEAF3FF;
            border = 0;
        }
        if (i == hot) {
            bg = COL_AMBER;
            fg = COL_ON;
            border = 0;
        }
        if (i == GARAGE_DIR_DOCK) {
            border = 2;
            border_c = (i == hot) ? COL_ON : COL_AMBER;
        }

        lv_obj_set_style_bg_color(orbit->pill[i], lv_color_hex(bg), 0);
        lv_obj_set_style_text_color(orbit->name[i], lv_color_hex(fg), 0);
        lv_obj_set_style_border_width(orbit->pill[i], border, 0);
        lv_obj_set_style_border_color(orbit->pill[i], lv_color_hex(border_c), 0);
        lv_label_set_text(orbit->name[i], garage_bay_short(i));
        lv_obj_center(orbit->name[i]);
    }
    lv_label_set_text(orbit->core_n, hero);
    lv_label_set_text(orbit->core_s, cap);
}

static void orbit_progress(orbit_t *orbit, int percent, uint32_t color)
{
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;
    lv_arc_set_rotation(orbit->ring, 270);
    lv_arc_set_angles(orbit->ring, 0, (uint16_t)(percent * 360 / 100));
    lv_obj_set_style_arc_color(orbit->ring, lv_color_hex(color), LV_PART_INDICATOR);
}

static const char *dock_word(bay_state_t state)
{
    if (state == BAY_CAR) return "接车";
    if (state == BAY_TRAY) return "接盘";
    return "接空";
}

static lv_obj_t *page_screen(page_id_t page)
{
    switch (page) {
    case PAGE_MENU: return scr_menu;
    case PAGE_PARK: return scr_park;
    case PAGE_GET: return scr_get;
    case PAGE_PROG: return scr_prog;
    case PAGE_FAULT: return scr_fault;
    default: return scr_idle;
    }
}

static void radar_set(int on)
{
    if (!orb_idle.ring || on == radar_on) return;
    radar_on = on;
    lv_anim_del(orb_idle.ring, sweep_cb);
    if (!on) {
        lv_arc_set_rotation(orb_idle.ring, 270);
        lv_arc_set_angles(orb_idle.ring, 0, 0);
        return;
    }
    lv_arc_set_angles(orb_idle.ring, 0, 32);

    lv_anim_t anim;

    lv_anim_init(&anim);
    lv_anim_set_var(&anim, orb_idle.ring);
    lv_anim_set_exec_cb(&anim, sweep_cb);
    lv_anim_set_values(&anim, 0, 360);
    lv_anim_set_time(&anim, 4800);
    lv_anim_set_repeat_count(&anim, LV_ANIM_REPEAT_INFINITE);
    lv_anim_set_path_cb(&anim, lv_anim_path_linear);
    lv_anim_start(&anim);
}

static void apply_page(int animate)
{
    lv_obj_t *screen;

    switch (g.page) {
    case PAGE_MENU: refresh_menu(); break;
    case PAGE_PARK: refresh_park(); break;
    case PAGE_GET: refresh_get(); break;
    case PAGE_PROG: refresh_prog(); break;
    case PAGE_FAULT: refresh_fault(); break;
    default: refresh_idle(); break;
    }
    /* The idle sweep invalidates every frame. Keep it off other pages so
     * the 168 MHz software renderer is not redrawing the menu for nothing. */
    radar_set(g.page == PAGE_IDLE);

    screen = page_screen(g.page);
    if (lv_scr_act() == screen) return;
    if (animate) lv_scr_load_anim(screen, LV_SCR_LOAD_ANIM_FADE_ON, 140, 0, false);
    else lv_scr_load(screen);
}

static void refresh_idle(void)
{
    char hero[8];

    lv_label_set_text_fmt(lab_hh, "%02d", g_h);
    lv_label_set_text_fmt(lab_mm, "%02d", g_m);
    lv_obj_set_style_bg_opa(colon_bar, g_colon_on ? LV_OPA_COVER : LV_OPA_20, 0);
    if (g_wday < 0 || g_wday > 6) g_wday = 0;
    lv_label_set_text_fmt(lab_date, "%s  %02d-%02d", k_week[g_wday], g_mon, g_mday);
    lv_label_set_text_fmt(lab_use, "在库 %02d", garage_count_cars(&g));
    lv_label_set_text_fmt(leg_lab[0], "空%d", garage_count_empty(&g));
    lv_label_set_text_fmt(leg_lab[1], "盘%d", garage_count_trays(&g));
    lv_label_set_text_fmt(leg_lab[2], "车%d", garage_count_cars(&g));
    lv_label_set_text(leg_lab[3], dock_word(garage_dock(&g)));
    snprintf(hero, sizeof hero, "%02d", garage_count_empty(&g));
    orbit_paint(&orb_idle, -1, hero, "空位");
}

static void style_menu(int index, int on, int warn)
{
    lv_obj_set_style_bg_color(menu_row[index], lv_color_hex(on ? COL_AMBER : COL_CARD), 0);
    lv_obj_set_style_bg_color(menu_accent[index],
        lv_color_hex(on ? 0x8A5A10 : k_accent[index]), 0);
    lv_obj_set_style_text_color(menu_title[index], lv_color_hex(on ? COL_ON : COL_INK), 0);
    lv_obj_set_style_text_color(menu_sub[index],
        lv_color_hex(on ? COL_ON_DIM : (warn ? COL_WARN : COL_DIM)), 0);
    lv_obj_set_style_text_color(menu_val[index], lv_color_hex(on ? COL_ON : COL_AMBER), 0);
}

static void refresh_menu(void)
{
    char sub[48];
    int warn;
    int i;
    int dock_car = garage_dock(&g) == BAY_CAR;

    for (i = 0; i < GARAGE_MENU_N; i++) {
        garage_block_t block;
        warn = 0;
        if (i == 0) {
            block = garage_park_block(&g);
            lv_obj_set_style_text_font(menu_val[i], &lv_font_montserrat_28, 0);
            lv_label_set_text_fmt(menu_val[i], "%02d", garage_count_empty(&g));
            if (block == BLOCK_DOCK_CAR) {
                snprintf(sub, sizeof sub, "对接有车");
                warn = 1;
            } else if (block == BLOCK_NO_EMPTY) {
                snprintf(sub, sizeof sub, "无空位");
                warn = 1;
            } else if (block == BLOCK_NO_TRAY) {
                snprintf(sub, sizeof sub, "无托盘");
                warn = 1;
            } else if (block == BLOCK_FETCH) {
                snprintf(sub, sizeof sub, "先调托盘");
            } else {
                snprintf(sub, sizeof sub, "空位 %02d  托盘 %02d",
                    garage_count_empty(&g), garage_count_trays(&g));
            }
        } else if (i == 1) {
            block = garage_get_block(&g);
            lv_obj_set_style_text_font(menu_val[i], &lv_font_montserrat_28, 0);
            lv_label_set_text_fmt(menu_val[i], "%02d", garage_count_cars(&g));
            if (block == BLOCK_DOCK_CAR) {
                snprintf(sub, sizeof sub, "对接有车");
                warn = 1;
            } else if (block == BLOCK_NO_CAR) {
                snprintf(sub, sizeof sub, "库内无车");
                warn = 1;
            } else if (block == BLOCK_NO_STASH) {
                snprintf(sub, sizeof sub, "托盘无处放");
                warn = 1;
            } else {
                snprintf(sub, sizeof sub, "在库 %02d 辆", garage_count_cars(&g));
            }
        } else if (dock_car) {
            lv_label_set_text(menu_title[i], "驶离");
            lv_obj_set_style_text_font(menu_val[i], &font_garage_16, 0);
            lv_label_set_text(menu_val[i], "确认");
            snprintf(sub, sizeof sub, "确认车已开走");
        } else {
            lv_label_set_text(menu_title[i], "待命");
            lv_obj_set_style_text_font(menu_val[i], &font_garage_16, 0);
            lv_label_set_text(menu_val[i], "返回");
            snprintf(sub, sizeof sub, "回到时钟");
        }
        lv_label_set_text(menu_sub[i], sub);
        style_menu(i, i == g.menu, warn);
    }
    paint_hint(menu_hint, "上下选择  右确认  左返回");
}

static void refresh_park(void)
{
    char hero[8];
    int focus = garage_model_focus_bay(&g);

    if (g.park_phase == PARK_DOCK) {
        lv_label_set_text(park_phase, "对接提示");
        lv_label_set_text(park_l1, "托盘已在对接位");
        lv_label_set_text(park_l2, "请把车开上托盘");
        snprintf(hero, sizeof hero, "DK");
        orbit_paint(&orb_park, focus, hero, "托盘");
        paint_hint(park_hint, "右键确认停好  左键返回");
        return;
    }

    lv_label_set_text(park_phase, "选择空位");
    lv_label_set_text_fmt(park_l1, "目标 %s", garage_bay_name(focus));
    lv_label_set_text_fmt(park_l2, "空位 %d/%d",
        g.park_n ? g.park_i + 1 : 0, g.park_n);
    snprintf(hero, sizeof hero, "%s", garage_bay_short(focus));
    orbit_paint(&orb_park, focus, hero, "空位");
    paint_hint(park_hint, "上下选位  右键开始  左返回");
}

static void refresh_get(void)
{
    int i;

    lv_label_set_text_fmt(get_count, "%d/%d", g.get_n ? g.get_i + 1 : 0, g.get_n);
    lv_label_set_text(get_sub, garage_dock(&g) == BAY_TRAY ? "先送回对接托盘" : "对接已空");
    for (i = 0; i < GARAGE_STORE_N; i++) {
        int on;

        if (i >= g.get_n) {
            lv_obj_add_flag(get_row[i], LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        on = (i == g.get_i);
        lv_obj_clear_flag(get_row[i], LV_OBJ_FLAG_HIDDEN);
        lv_obj_set_pos(get_row[i], 8, 52 + i * 22);
        lv_label_set_text_fmt(get_idx[i], "%d", i + 1);
        lv_label_set_text(get_name[i], garage_bay_name(g.get_map[i]));
        lv_label_set_text(get_tag[i], "有车");
        lv_obj_set_style_bg_color(get_row[i], lv_color_hex(on ? COL_AMBER : COL_CARD), 0);
        lv_obj_set_style_text_color(get_idx[i], lv_color_hex(on ? COL_ON : COL_AMBER), 0);
        lv_obj_set_style_text_color(get_name[i], lv_color_hex(on ? COL_ON : COL_INK), 0);
        lv_obj_set_style_text_color(get_tag[i], lv_color_hex(on ? COL_ON : COL_MINT), 0);
    }
    paint_hint(get_hint, "上下选择  右键取出  左返回");
}

static void refresh_prog(void)
{
    char line[64];
    char hero[8];
    int hold = g.prog_phase == PROG_HOLD;
    int focus = garage_model_focus_bay(&g);
    const char *cap = "进度";
    const char *normal;

    if (hold && g.job == JOB_GET) lv_label_set_text(prog_title, "请取车");
    else if (hold) lv_label_set_text(prog_title, "已完成");
    else if (g.job == JOB_PARK) lv_label_set_text(prog_title, "存车中");
    else lv_label_set_text(prog_title, "取车中");

    if (hold) lv_label_set_text(prog_frac, "完成");
    else lv_label_set_text_fmt(prog_frac, "%d/4", garage_model_step_index(&g) + 1);

    garage_model_step_line(&g, line, sizeof line);
    lv_label_set_text(prog_step, line);

    if (hold) cap = "完成";
    else if (g.job == JOB_PARK && g.prog >= 50 && g.prog < 75) cap = "在途";

    snprintf(hero, sizeof hero, "%d", g.prog);
    orbit_progress(&orb_prog, g.prog, hold ? COL_MINT : COL_AMBER);
    orbit_paint(&orb_prog, focus, hero, cap);

    if (g.prog_phase == PROG_RUN) normal = "左键中止";
    else if (g.job == JOB_GET) normal = "右键确认驶离  左键稍后";
    else normal = "任意键返回";
    paint_hint(prog_hint, normal);
}

static void refresh_fault(void)
{
    lv_label_set_text(fault_code, garage_fault_code(g.fault));
    lv_label_set_text(fault_title, garage_fault_title(g.fault));
    lv_label_set_text(fault_body, garage_fault_body(g.fault));
    lv_label_set_text(fault_action, garage_fault_action(&g));
    lv_obj_center(fault_action);
    paint_hint(fault_hint, "左键返回");
}

static void on_key(key_id_t key)
{
    int job_was_idle = (g.job == JOB_NONE);

    note_in();
    garage_model_on_key(&g, key);
    capture_note();
    if (job_was_idle && g.job != JOB_NONE) {
        lv_timer_resume(job_timer);
        lv_timer_reset(job_timer);
    }
    if (g.job == JOB_NONE) lv_timer_pause(job_timer);
    apply_page(1);
}

static uint8_t key_read(void)
{
    if (rt_pin_read(PIN_KEY_LEFT) == PIN_LOW) return KEY_LEFT;
    if (rt_pin_read(PIN_KEY_RIGHT) == PIN_LOW) return KEY_RIGHT;
    if (rt_pin_read(PIN_KEY_UP) == PIN_LOW) return KEY_UP;
    if (rt_pin_read(PIN_KEY_DOWN) == PIN_LOW) return KEY_DOWN;
    return KEY_NONE;
}

static void key_cb(lv_timer_t *timer)
{
    static uint8_t raw_prev = 0xFF;
    static uint8_t raw_count = 0;
    static uint8_t stable = KEY_NONE;
    uint8_t raw = key_read();

    (void)timer;
    if (raw == raw_prev) {
        if (raw_count < 3) raw_count++;
    } else {
        raw_prev = raw;
        raw_count = 1;
    }
    if (raw_count >= 2 && raw != stable) {
        if (raw != KEY_NONE) on_key((key_id_t)raw);
        stable = raw;
    }

    if (s_note != NOTE_NONE && lv_tick_elaps(s_note_t) >= NOTE_MS) {
        s_note = NOTE_NONE;
        apply_page(0);
    }
    if (garage_model_allow_idle_timeout(&g) && lv_tick_elaps(g_last_in) >= IDLE_TIMEOUT_MS) {
        garage_model_on_idle_timeout(&g);
        note_in();
        s_note = NOTE_NONE;
        apply_page(1);
    }
}

static void job_cb(lv_timer_t *timer)
{
    int result;

    (void)timer;
    result = garage_model_job_tick(&g);
    if (result == 0) {
        if (g.page == PAGE_PROG) refresh_prog();
        return;
    }
    note_in();
    if (g.job == JOB_NONE) lv_timer_pause(job_timer);
    apply_page(result == 2);
}

static void clk_cb(lv_timer_t *timer)
{
    (void)timer;
    tick_clk();
    if (g.page == PAGE_IDLE) refresh_idle();
}

static void build_legend(lv_obj_t *parent)
{
    static const uint32_t chip_bg[4] = { COL_EMPTY, COL_TRAY, COL_CAR, COL_CARD };
    static const int chip_border[4] = { 1, 0, 0, 2 };
    int i;

    for (i = 0; i < 4; i++) {
        lv_obj_t *chip = lv_obj_create(parent);

        flat(chip);
        lv_obj_set_size(chip, 10, 10);
        lv_obj_set_pos(chip, 14 + i * 58, 224);
        lv_obj_set_style_radius(chip, i == 3 ? 2 : 5, 0);
        lv_obj_set_style_bg_color(chip, lv_color_hex(chip_bg[i]), 0);
        lv_obj_set_style_bg_opa(chip, LV_OPA_COVER, 0);
        lv_obj_set_style_border_width(chip, chip_border[i], 0);
        lv_obj_set_style_border_color(chip,
            lv_color_hex(i == 3 ? COL_AMBER : COL_LINE), 0);

        leg_lab[i] = mk_label(parent, &font_garage_16, COL_INK, "");
        lv_obj_set_pos(leg_lab[i], 28 + i * 58, 220);
    }
}

static void build_idle(void)
{
    lv_obj_t *row;

    lv_obj_t *brand;
    lv_obj_t *enter;

    scr_idle = make_screen(COL_AMBER);

    brand = mk_label(scr_idle, &font_garage_16, COL_AMBER, "星火车库");
    lv_obj_align(brand, LV_ALIGN_TOP_LEFT, 12, 8);
    enter = mk_label(scr_idle, &font_garage_16, COL_DIM, "按任意键");
    lv_obj_align(enter, LV_ALIGN_TOP_RIGHT, -10, 8);

    row = lv_obj_create(scr_idle);
    flat(row);
    lv_obj_set_size(row, 224, 50);
    lv_obj_align(row, LV_ALIGN_TOP_MID, 0, 28);
    lv_obj_set_style_bg_opa(row, LV_OPA_TRANSP, 0);

    lab_hh = mk_label(row, &lv_font_montserrat_48, COL_INK, "21");
    lv_obj_align(lab_hh, LV_ALIGN_CENTER, -50, 0);
    lab_mm = mk_label(row, &lv_font_montserrat_48, COL_INK, "06");
    lv_obj_align(lab_mm, LV_ALIGN_CENTER, 50, 0);
    colon_bar = lv_obj_create(row);
    flat(colon_bar);
    lv_obj_set_size(colon_bar, 4, 26);
    lv_obj_set_style_radius(colon_bar, 2, 0);
    lv_obj_set_style_bg_color(colon_bar, lv_color_hex(COL_AMBER), 0);
    lv_obj_set_style_bg_opa(colon_bar, LV_OPA_COVER, 0);
    lv_obj_align(colon_bar, LV_ALIGN_CENTER, 0, 0);

    lab_date = mk_label(scr_idle, &font_garage_16, COL_DIM, "");
    lv_obj_align(lab_date, LV_ALIGN_TOP_LEFT, 12, 80);
    lab_use = mk_label(scr_idle, &font_garage_16, COL_MINT, "");
    lv_obj_align(lab_use, LV_ALIGN_TOP_RIGHT, -10, 80);

    orbit_build(scr_idle, &orb_idle, IDLE_CX, IDLE_CY, IDLE_R);
    build_legend(scr_idle);
}

static void build_menu(void)
{
    static const char *titles[GARAGE_MENU_N] = { "存车", "取车", "待命" };
    int i;

    scr_menu = make_screen(COL_AMBER);
    for (i = 0; i < GARAGE_MENU_N; i++) {
        lv_obj_t *row = lv_obj_create(scr_menu);
        lv_obj_t *accent;
        lv_obj_t *title;
        lv_obj_t *sub;
        lv_obj_t *val;

        flat(row);
        lv_obj_set_size(row, 224, 64);
        lv_obj_set_pos(row, 8, 8 + i * 70);
        lv_obj_set_style_radius(row, 12, 0);
        lv_obj_set_style_clip_corner(row, true, 0);
        lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);

        accent = lv_obj_create(row);
        flat(accent);
        lv_obj_set_size(accent, 5, 64);
        lv_obj_align(accent, LV_ALIGN_LEFT_MID, 0, 0);
        lv_obj_set_style_bg_opa(accent, LV_OPA_COVER, 0);

        title = mk_label(row, &font_garage_20, COL_INK, titles[i]);
        lv_obj_align(title, LV_ALIGN_TOP_LEFT, 16, 8);
        sub = mk_label(row, &font_garage_16, COL_DIM, "");
        lv_obj_set_width(sub, 196);
        lv_label_set_long_mode(sub, LV_LABEL_LONG_CLIP);
        lv_obj_align(sub, LV_ALIGN_TOP_LEFT, 16, 36);
        val = mk_label(row, &lv_font_montserrat_28, COL_AMBER, "00");
        lv_obj_align(val, LV_ALIGN_TOP_RIGHT, -12, 6);

        menu_row[i] = row;
        menu_accent[i] = accent;
        menu_title[i] = title;
        menu_sub[i] = sub;
        menu_val[i] = val;
    }
    menu_hint = mk_footer(scr_menu);
}

static void build_park(void)
{
    lv_obj_t *title;
    lv_obj_t *card;

    scr_park = make_screen(COL_AMBER);
    title = mk_label(scr_park, &font_garage_20, COL_INK, "存车");
    lv_obj_align(title, LV_ALIGN_TOP_LEFT, 12, 8);
    park_phase = mk_label(scr_park, &font_garage_16, COL_AMBER, "");
    lv_obj_align(park_phase, LV_ALIGN_TOP_RIGHT, -10, 12);

    orbit_build(scr_park, &orb_park, WORK_CX, WORK_CY, WORK_R);

    card = lv_obj_create(scr_park);
    flat(card);
    lv_obj_set_size(card, 224, 46);
    lv_obj_align(card, LV_ALIGN_TOP_MID, 0, 166);
    lv_obj_set_style_radius(card, 10, 0);
    lv_obj_set_style_bg_color(card, lv_color_hex(COL_CARD), 0);
    lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
    park_l1 = mk_label(card, &font_garage_16, COL_INK, "");
    lv_obj_align(park_l1, LV_ALIGN_TOP_LEFT, 10, 4);
    park_l2 = mk_label(card, &font_garage_16, COL_DIM, "");
    lv_obj_align(park_l2, LV_ALIGN_TOP_LEFT, 10, 24);
    park_hint = mk_footer(scr_park);
}

static void build_get(void)
{
    lv_obj_t *title;
    int i;

    scr_get = make_screen(COL_AMBER);
    title = mk_label(scr_get, &font_garage_20, COL_INK, "取车");
    lv_obj_align(title, LV_ALIGN_TOP_LEFT, 12, 8);
    get_count = mk_label(scr_get, &font_garage_16, COL_AMBER, "");
    lv_obj_align(get_count, LV_ALIGN_TOP_RIGHT, -10, 12);
    get_sub = mk_label(scr_get, &font_garage_16, COL_DIM, "");
    lv_obj_align(get_sub, LV_ALIGN_TOP_LEFT, 12, 32);

    for (i = 0; i < GARAGE_STORE_N; i++) {
        lv_obj_t *row = lv_obj_create(scr_get);

        flat(row);
        lv_obj_set_size(row, 224, 20);
        lv_obj_set_style_radius(row, 8, 0);
        lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
        get_idx[i] = mk_label(row, &lv_font_montserrat_14, COL_AMBER, "");
        lv_obj_align(get_idx[i], LV_ALIGN_LEFT_MID, 8, 0);
        get_name[i] = mk_label(row, &font_garage_16, COL_INK, "");
        lv_obj_align(get_name[i], LV_ALIGN_LEFT_MID, 28, 0);
        get_tag[i] = mk_label(row, &font_garage_16, COL_MINT, "有车");
        lv_obj_align(get_tag[i], LV_ALIGN_RIGHT_MID, -8, 0);
        get_row[i] = row;
        lv_obj_add_flag(row, LV_OBJ_FLAG_HIDDEN);
    }
    get_hint = mk_footer(scr_get);
}

static void build_prog(void)
{
    scr_prog = make_screen(COL_AMBER);
    prog_title = mk_label(scr_prog, &font_garage_20, COL_INK, "");
    lv_obj_align(prog_title, LV_ALIGN_TOP_LEFT, 12, 8);
    prog_frac = mk_label(scr_prog, &font_garage_16, COL_AMBER, "");
    lv_obj_align(prog_frac, LV_ALIGN_TOP_RIGHT, -10, 12);
    prog_step = mk_label(scr_prog, &font_garage_16, COL_INK, "");
    lv_obj_set_width(prog_step, 216);
    lv_label_set_long_mode(prog_step, LV_LABEL_LONG_CLIP);
    lv_obj_align(prog_step, LV_ALIGN_TOP_LEFT, 12, 34);
    orbit_build(scr_prog, &orb_prog, PROG_CX, PROG_CY, PROG_R);
    prog_hint = mk_footer(scr_prog);
}

static void build_fault(void)
{
    lv_obj_t *kicker;
    lv_obj_t *card;

    scr_fault = make_screen(COL_RED);
    kicker = mk_label(scr_fault, &font_garage_16, COL_RED, "故障");
    lv_obj_align(kicker, LV_ALIGN_TOP_MID, 0, 14);
    fault_code = mk_label(scr_fault, &lv_font_montserrat_48, COL_INK, "E00");
    lv_obj_align(fault_code, LV_ALIGN_TOP_MID, 0, 36);
    fault_title = mk_label(scr_fault, &font_garage_20, COL_INK, "");
    lv_obj_align(fault_title, LV_ALIGN_TOP_MID, 0, 96);
    fault_body = mk_label(scr_fault, &font_garage_16, COL_DIM, "");
    lv_obj_set_width(fault_body, 216);
    lv_label_set_long_mode(fault_body, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_align(fault_body, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(fault_body, LV_ALIGN_TOP_MID, 0, 126);

    card = lv_obj_create(scr_fault);
    flat(card);
    lv_obj_set_size(card, 216, 36);
    lv_obj_align(card, LV_ALIGN_TOP_MID, 0, 168);
    lv_obj_set_style_radius(card, 10, 0);
    lv_obj_set_style_bg_color(card, lv_color_hex(COL_CARD), 0);
    lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(card, 1, 0);
    lv_obj_set_style_border_color(card, lv_color_hex(COL_AMBER), 0);
    fault_action = mk_label(card, &font_garage_16, COL_AMBER, "");
    lv_obj_center(fault_action);
    fault_hint = mk_footer(scr_fault);
}

void garage_ui_init(void)
{
    rt_pin_mode(PIN_KEY_LEFT, PIN_MODE_INPUT_PULLUP);
    rt_pin_mode(PIN_KEY_RIGHT, PIN_MODE_INPUT_PULLUP);
    rt_pin_mode(PIN_KEY_UP, PIN_MODE_INPUT_PULLUP);
    rt_pin_mode(PIN_KEY_DOWN, PIN_MODE_INPUT_PULLUP);

    garage_model_init(&g);
    build_idle();
    build_menu();
    build_park();
    build_get();
    build_prog();
    build_fault();

    sync_rtc();
    note_in();
    apply_page(0);

    job_timer = lv_timer_create(job_cb, 200, NULL);
    lv_timer_pause(job_timer);
    lv_timer_create(key_cb, 30, NULL);
    lv_timer_create(clk_cb, 1000, NULL);

    rt_kprintf("[garage_ui] tower deck ready\n");
}
