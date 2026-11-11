/*
 * hmi_tjc.c - UI backend for the TJC4827T143 serial screen on USART3.
 *
 * Design rule: the screen holds no logic. Every touch only reports an event
 * frame; this file decides which page is shown and pushes every value.
 * Only values that changed since the last push are sent (shadow cache), and
 * the cache is dropped whenever the page changes or the screen restarts.
 *
 * Control names, page ids and picture ids are specified in
 * docs/串口屏界面_v1/README.md.
 */
#include <rtthread.h>
#include <rtdevice.h>
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>
#include <sys/time.h>

#include "ui_model.h"
#include "hmi_proto.h"
#include "hmi_res.h"
#include "hmi_text.h"
#include "hmi_tjc.h"

#define DBG_TAG "hmi"
#define DBG_LVL DBG_INFO
#include <rtdbg.h>

#define HMI_UART_NAME       "uart3"
#define HMI_BAUD            BAUD_RATE_115200
#define HMI_TICK_MS         100
#define HMI_BLINK_TICKS     5           /* 0.5 s */
#define HMI_IDLE_MS         60000       /* no touch -> standby page */
#define HMI_TITLE_HOLD_MS   3000        /* long press on the title -> password page */
#define HMI_OFFLINE_MS      3500        /* no heartbeat -> screen considered offline */
#define HMI_DIM_ACTIVE      100
#define HMI_DIM_IDLE        30

#define COL_OK      HMI_RGB565(0x34, 0xD3, 0x99)
#define COL_OFF     HMI_RGB565(0x1A, 0x27, 0x40)
#define COL_CARD    HMI_RGB565(0x13, 0x1D, 0x31)
#define COL_ACC     HMI_RGB565(0x22, 0xD3, 0xEE)
#define COL_TEXT    HMI_RGB565(0xE8, 0xF0, 0xFA)
#define COL_DARK    HMI_RGB565(0x03, 0x13, 0x1D)

enum { VIEW_MAIN = 0, VIEW_PWD, VIEW_JOG, VIEW_CAL, VIEW_SEN };
enum { PM_HOME = 0, PM_SEL, PM_DOCK_PUT, PM_DOCK_TAKE, PM_PROG, PM_NONE = 0xFF };

/* Shadow cache slots: one per value pushed to the screen. */
enum {
    SH_BAY0 = 0, SH_HUB = 8, SH_CLK, SH_TABS,
    SH_FREE, SH_TOTAL, SH_OCC, SH_STORE_EN,
    SH_SEL, SH_ROW_TRAY, SH_ROW_HAND, SH_OK_EN, SH_TAKEN_EN,
    SH_JOB, SH_STEP, SH_IDX, SH_BAR, SH_ETA,
    SH_F_TEXT, SH_F_CHK0, SH_F_CHK1, SH_F_HOME,
    SH_PIN,
    SH_POS0, SH_POS1, SH_POS2, SH_JSTEP,
    SH_CAL_BAY, SH_CAL_HS, SH_CAL_AS,
    SH_LAMP0, SH_DIM = SH_LAMP0 + 16,
    SH__COUNT
};
#define SH_INVALID  ((rt_int32_t)0x7FFFFFFF)

static rt_device_t s_dev;
static struct rt_semaphore s_rx_sem;
static struct hmi_parser s_parser;
static rt_int32_t s_shadow[SH__COUNT];
static char s_pin[5] = "0000";          /* maintenance PIN, change with msh: hmi_pin */

static struct {
    rt_uint8_t page;                    /* page we last commanded, 0xFF = unknown */
    rt_uint8_t view;
    rt_uint8_t panel;                   /* right panel mode currently drawn */
    rt_uint8_t layer;                   /* layer shown on the map */
    rt_int8_t  sel_layer, sel_dir;      /* selected car, sel_dir < 0 = none */
    rt_uint8_t chk;                     /* fault page manual checks, bit0 / bit1 */
    char       pin[4];
    rt_uint8_t pin_len;
    rt_uint8_t jog_step;                /* 0 / 1 / 2 -> 1 / 10 / 100 */
    rt_uint8_t cal_layer, cal_dir;
    rt_uint8_t idle;
    rt_uint8_t online;
    rt_uint8_t title_down;
    rt_uint8_t blink;
    rt_uint8_t blink_cnt;
    rt_tick_t  t_activity, t_title, t_heartbeat;
} v;

static const rt_int32_t k_jog_steps[3] = { 1, 10, 100 };

/* ------------------------------------------------------------------ tx */

static void tx(const char *fmt, ...)
{
    char buf[112];
    va_list ap;
    int n;
    size_t len;

    va_start(ap, fmt);
    n = rt_vsnprintf(buf, sizeof(buf) - 3, fmt, ap);
    va_end(ap);
    if (n < 0)
        return;
    if (n > (int)sizeof(buf) - 4)
        n = sizeof(buf) - 4;
    len = hmi_terminate(buf, (size_t)n, sizeof(buf));
    if (len && s_dev)
        rt_device_write(s_dev, 0, buf, len);
}

static void shadow_reset(void)
{
    int i;
    rt_int32_t dim = s_shadow[SH_DIM];

    for (i = 0; i < SH__COUNT; i++)
        s_shadow[i] = SH_INVALID;
    s_shadow[SH_DIM] = dim;             /* backlight survives page changes */
}

/* Returns 1 when the value differs from what the screen already shows. */
static int changed(int slot, rt_int32_t val)
{
    if (s_shadow[slot] == val)
        return 0;
    s_shadow[slot] = val;
    return 1;
}

static void set_pic(int slot, const char *obj, int pic)
{
    if (changed(slot, pic))
        tx("%s.pic=%d", obj, pic);
}

static void set_val(int slot, const char *obj, rt_int32_t val)
{
    if (changed(slot, val))
        tx("%s.val=%d", obj, val);
}

/* Button with normal / pressed / disabled pictures. */
static void set_btn(int slot, const char *obj, int en, int pic, int pic_down, int pic_off)
{
    if (!changed(slot, en))
        return;
    tx("%s.pic=%d", obj, en ? pic : pic_off);
    tx("%s.pic2=%d", obj, en ? pic_down : pic_off);
    tx("tsw %s,%d", obj, en ? 1 : 0);
}

static void goto_page(rt_uint8_t page)
{
    if (v.page == page)
        return;
    tx("page %d", page);
    v.page = page;
    v.panel = PM_NONE;
    shadow_reset();
}

static void set_dim(int dim)
{
    if (changed(SH_DIM, dim))
        tx("dim=%d", dim);
}

/* ------------------------------------------------------------ helpers */

static void count_bays(const struct ui_state *s, int *free_n, int *total)
{
    int l, d, f = 0, t = 0;

    for (l = 0; l < s->layers && l < UI_LAYERS_MAX; l++) {
        for (d = 0; d < UI_DIRS; d++) {
            if (d == UI_DIR_DOCK || s->bay[l][d] == UI_BAY_NA)
                continue;
            t++;
            if (s->bay[l][d] != UI_BAY_CAR)
                f++;
        }
    }
    *free_n = f;
    *total = t;
}

/* Minutes since midnight, or -1 when the RTC has never been set. */
static int clock_minutes(void)
{
    time_t now;
    struct tm *ti;

    if (!rt_device_find("rtc"))
        return -1;
    now = time(RT_NULL);
    if (now < 100000)
        return -1;
    ti = localtime(&now);
    return ti ? ti->tm_hour * 60 + ti->tm_min : -1;
}

static void push_clock(void)
{
    int m = clock_minutes();

    if (!changed(SH_CLK, m))
        return;
    if (m < 0)
        tx("tClk.txt=\"--:--\"");
    else
        tx("tClk.txt=\"%02d:%02d\"", m / 60, m % 60);
}

static void push_occupancy(const struct ui_state *s)
{
    int f, t;

    count_bays(s, &f, &t);
    set_val(SH_FREE, "nFree", f);
    if (changed(SH_TOTAL, t)) {
        tx("tTot.txt=\"/ %d\"", t);
        /* The bar picture has one segment per bay: 7 for one layer, 14 for two. */
        tx("jOcc.bpic=%d", t > 7 ? PIC_OCC14_EMPTY : PIC_OCC7_EMPTY);
        tx("jOcc.ppic=%d", t > 7 ? PIC_OCC14_FULL : PIC_OCC7_FULL);
    }
    set_val(SH_OCC, "jOcc", t ? ((t - f) * 100 + t / 2) / t : 0);
}

static const struct hmi_fault_text *fault_text(rt_uint8_t code)
{
    const struct hmi_fault_text *f = k_hmi_fault;

    while (f->code != 0 && f->code != code)
        f++;
    return f;                           /* last entry (code 0) is the fallback */
}

static void sel_clear(void)
{
    v.sel_dir = -1;
}

/* ---------------------------------------------------------- main page */

static int bay_pic(const struct ui_state *s, int layer, int d, int pm)
{
    int st = s->bay[layer - 1][d];
    int idx;

    if (d == UI_DIR_DOCK) {
        if (layer != 1 || st == UI_BAY_NA)
            idx = BAY_ST_SHAFT;
        else if (pm == PM_DOCK_PUT || pm == PM_DOCK_TAKE)
            idx = BAY_ST_DOCK_ACTIVE;
        else
            idx = (st == UI_BAY_EMPTY) ? BAY_ST_EMPTY : BAY_ST_TRAY;
    } else {
        idx = (st == UI_BAY_CAR) ? BAY_ST_CAR : (st == UI_BAY_TRAY) ? BAY_ST_TRAY : BAY_ST_EMPTY;
        if (pm == PM_SEL && v.sel_layer == layer && v.sel_dir == d)
            idx = BAY_ST_SEL;
        if (pm == PM_PROG && s->job_layer == layer && s->job_dir == d && v.blink)
            idx = BAY_ST_TARGET;
    }
    return PIC_BAY_BASE + d * 5 + idx;
}

static const char *const k_panel_objs[] = {
    "nFree", "tTot", "jOcc", "bStore",              /* PM_HOME */
    "tSel", "bGet",                                 /* PM_SEL */
    "pTray", "pHand", "bOk", "bCancel", "bTaken",   /* PM_DOCK_* */
    "tJob", "tStep", "tIdx", "jStep", "nEta"        /* PM_PROG */
};
/* First index and count in k_panel_objs for each panel mode. */
static const rt_uint8_t k_panel_first[] = { 0, 4, 6, 6, 11 };
static const rt_uint8_t k_panel_count[] = { 4, 2, 4, 5, 5 };

static void panel_switch(int pm)
{
    unsigned i;

    if (v.panel == pm)
        return;
    /* Hide everything, repaint the panel body, then show this mode's controls. */
    for (i = 0; i < sizeof(k_panel_objs) / sizeof(k_panel_objs[0]); i++)
        tx("vis %s,0", k_panel_objs[i]);
    tx("vis tab1,0");
    tx("vis tab2,0");
    tx("pPanel.pic=%d", PIC_PANEL_HOME + pm);
    for (i = 0; i < k_panel_count[pm]; i++) {
        const char *obj = k_panel_objs[k_panel_first[pm] + i];
        if (pm == PM_DOCK_PUT && !strcmp(obj, "bTaken"))
            continue;
        if (pm == PM_DOCK_TAKE && (!strcmp(obj, "bOk") || !strcmp(obj, "bCancel")))
            continue;
        tx("vis %s,1", obj);
    }
    v.panel = pm;
    /* Controls were repainted: force their values to be sent again. */
    for (i = SH_FREE; i <= SH_ETA; i++)
        s_shadow[i] = SH_INVALID;
    s_shadow[SH_TABS] = SH_INVALID;
}

static void push_main(const struct ui_state *s)
{
    static const char *const bay_obj[UI_DIRS] = { "b0", "b1", "b2", "b3", "b4", "b5", "b6", "b7" };
    int pm, layer, d, blocked;
    char txt[64];

    switch (s->phase) {
    case UI_PH_DOCK_PUT:  pm = PM_DOCK_PUT;  layer = 1; break;
    case UI_PH_DOCK_TAKE: pm = PM_DOCK_TAKE; layer = 1; break;
    case UI_PH_RUN:       pm = PM_PROG;      layer = s->job_layer ? s->job_layer : 1; break;
    default:              pm = (v.sel_dir >= 0) ? PM_SEL : PM_HOME; layer = v.layer; break;
    }
    if (layer < 1 || layer > s->layers)
        layer = 1;
    v.layer = (rt_uint8_t)layer;

    push_clock();

    for (d = 0; d < UI_DIRS; d++)
        set_pic(SH_BAY0 + d, bay_obj[d], bay_pic(s, layer, d, pm));
    set_pic(SH_HUB, "hub", (s->lift_layer == layer && s->heading < UI_DIRS)
            ? PIC_HUB_BASE + s->heading : PIC_HUB_NONE);

    panel_switch(pm);
    blocked = (s->sensors & UI_SEN_DOCK_IR) != 0;

    /*
     * Layer tabs sit on top of the panel picture, so they are drawn after it.
     * They only show on the home / selected panels of a two-layer machine;
     * panel_switch() has already hidden them in every other case.
     */
    if (changed(SH_TABS, (s->layers > 1 && pm <= PM_SEL) ? layer : 0) && s->layers > 1 && pm <= PM_SEL) {
        tx("tab1.pic=%d", layer == 1 ? PIC_TAB1_ON : PIC_TAB1_OFF);
        tx("tab2.pic=%d", layer == 2 ? PIC_TAB2_ON : PIC_TAB2_OFF);
        tx("vis tab1,1");
        tx("vis tab2,1");
    }

    switch (pm) {
    case PM_HOME: {
        int f, t;
        count_bays(s, &f, &t);
        push_occupancy(s);
        set_btn(SH_STORE_EN, "bStore", f > 0, PIC_BTN_STORE, PIC_BTN_STORE_DOWN, PIC_BTN_STORE_OFF);
        break;
    }
    case PM_SEL:
        if (changed(SH_SEL, v.sel_layer * 16 + v.sel_dir)) {
            rt_snprintf(txt, sizeof(txt), HMI_TXT_BAY, v.sel_layer, k_hmi_dir[v.sel_dir]);
            tx("tSel.txt=\"%s\"", txt);
        }
        break;
    case PM_DOCK_PUT:
    case PM_DOCK_TAKE:
        set_pic(SH_ROW_TRAY, "pTray",
                s->bay[0][UI_DIR_DOCK] != UI_BAY_EMPTY ? PIC_ROW_TRAY_OK : PIC_ROW_TRAY_WAIT);
        set_pic(SH_ROW_HAND, "pHand", blocked ? PIC_ROW_HAND_BLOCK : PIC_ROW_HAND_CLEAR);
        if (pm == PM_DOCK_PUT)
            set_btn(SH_OK_EN, "bOk", !blocked, PIC_BTN_OK, PIC_BTN_OK_DOWN, PIC_BTN_OK_OFF);
        else
            set_btn(SH_TAKEN_EN, "bTaken", !blocked, PIC_BTN_TAKEN, PIC_BTN_TAKEN_DOWN, PIC_BTN_TAKEN_OFF);
        break;
    case PM_PROG:
        if (changed(SH_JOB, (s->job << 16) | (s->job_layer << 8) | s->job_dir)) {
            if (s->job == UI_JOB_NONE || s->job_dir >= UI_DIRS)
                rt_snprintf(txt, sizeof(txt), "%s", HMI_TXT_JOB_HOME);
            else
                rt_snprintf(txt, sizeof(txt), s->job == UI_JOB_STORE ? HMI_TXT_JOB_STORE : HMI_TXT_JOB_GET,
                            s->job_layer, k_hmi_dir[s->job_dir]);
            tx("tJob.txt=\"%s\"", txt);
        }
        if (changed(SH_STEP, (s->step << 16) | (s->job_layer << 8) | s->job_dir)) {
            rt_uint8_t st = s->step < UI_STEP__COUNT ? s->step : UI_STEP_NONE;
            if (st == UI_STEP_ROTATE_TO_BAY)
                rt_snprintf(txt, sizeof(txt), k_hmi_step[st], k_hmi_dir[s->job_dir < UI_DIRS ? s->job_dir : 0]);
            else if (st == UI_STEP_LIFT_TO_LAYER)
                rt_snprintf(txt, sizeof(txt), k_hmi_step[st], s->job_layer);
            else
                rt_snprintf(txt, sizeof(txt), "%s", k_hmi_step[st]);
            tx("tStep.txt=\"%s\"", txt);
        }
        if (changed(SH_IDX, s->step_idx * 256 + s->step_total))
            tx("tIdx.txt=\"%d / %d\"", s->step_idx, s->step_total);
        set_val(SH_BAR, "jStep", s->step_total ? s->step_idx * 100 / s->step_total : 0);
        set_val(SH_ETA, "nEta", s->eta_s);
        break;
    }
}

/* -------------------------------------------------------- other pages */

static void push_fault(const struct ui_state *s)
{
    char txt[96];
    int n = 0;

    push_clock();
    if (changed(SH_F_TEXT, (s->fault << 16) | (s->job_layer << 8) | s->job_dir)) {
        const struct hmi_fault_text *f = fault_text(s->fault);

        tx("tCode.txt=\"E%02d\"", s->fault);
        tx("tTitle.txt=\"%s\"", f->title);
        if (s->job != UI_JOB_NONE && s->job_dir < UI_DIRS && s->job_layer)
            n = rt_snprintf(txt, sizeof(txt), HMI_TXT_FAULT_AT, s->job_layer, k_hmi_dir[s->job_dir], s->step_idx);
        rt_snprintf(txt + n, sizeof(txt) - n, "%s", f->hint);
        tx("tDesc.txt=\"%s\"", txt);
    }
    set_pic(SH_F_CHK0, "c0", (v.chk & 1) ? PIC_CHK0_ON : PIC_CHK0_OFF);
    set_pic(SH_F_CHK1, "c1", (v.chk & 2) ? PIC_CHK1_ON : PIC_CHK1_OFF);
    set_btn(SH_F_HOME, "bHome", v.chk == 3, PIC_BTN_HOME, PIC_BTN_HOME_DOWN, PIC_BTN_HOME_OFF);
}

static void push_idle(const struct ui_state *s)
{
    push_clock();
    push_occupancy(s);
}

static void push_pwd(void)
{
    static const char *const obj[4] = { "d0", "d1", "d2", "d3" };
    int i;

    if (!changed(SH_PIN, v.pin_len))
        return;
    for (i = 0; i < 4; i++)
        tx("%s.pic=%d", obj[i], i < v.pin_len ? PIC_PIN_FULL : PIC_PIN_EMPTY);
}

static void push_jog(const struct ui_state *s)
{
    static const char *const obj[3] = { "n0", "n1", "n2" };
    int i;

    for (i = 0; i < 3; i++)
        set_val(SH_POS0 + i, obj[i], s->axis_pos[i]);
    if (changed(SH_JSTEP, v.jog_step)) {
        for (i = 0; i < 3; i++) {
            tx("s%d.bco=%d", i, i == v.jog_step ? COL_ACC : COL_CARD);
            tx("s%d.pco=%d", i, i == v.jog_step ? COL_DARK : COL_TEXT);
        }
    }
}

static void push_cal(const struct ui_state *s)
{
    rt_int32_t h = 0, a = 0;
    char txt[32];

    if (changed(SH_CAL_BAY, v.cal_layer * 16 + v.cal_dir)) {
        rt_snprintf(txt, sizeof(txt), HMI_TXT_BAY, v.cal_layer, k_hmi_dir[v.cal_dir]);
        tx("tBay.txt=\"%s\"", txt);
    }
    garage_ui_get_cal(v.cal_layer, v.cal_dir, &h, &a);
    set_val(SH_POS0, "nHc", s->axis_pos[UI_AXIS_LIFT]);
    set_val(SH_POS1, "nAc", s->axis_pos[UI_AXIS_ROTATE]);
    set_val(SH_CAL_HS, "nHs", h);
    set_val(SH_CAL_AS, "nAs", a);
}

static void push_sen(const struct ui_state *s)
{
    int i;

    for (i = 0; i < 16; i++) {
        int on = (s->sensors >> i) & 1;
        if (changed(SH_LAMP0 + i, on))
            tx("l%d.bco=%d", i, on ? COL_OK : COL_OFF);
    }
}

/* ------------------------------------------------------------- events */

static void post(rt_uint8_t id, rt_uint8_t a, rt_uint8_t b, rt_int32_t val)
{
    struct ui_cmd c;

    c.id = id;
    c.a = a;
    c.b = b;
    c.v = val;
    if (garage_ui_post_cmd(&c) != 0)
        LOG_W("command %d rejected", id);
}

static void cal_step(const struct ui_state *s, int forward)
{
    int n = s->layers * UI_DIRS, i;
    int pos = (v.cal_layer - 1) * UI_DIRS + v.cal_dir;

    for (i = 0; i < n; i++) {
        pos = (pos + (forward ? 1 : n - 1)) % n;
        if (pos % UI_DIRS != UI_DIR_DOCK)
            break;
    }
    v.cal_layer = (rt_uint8_t)(pos / UI_DIRS + 1);
    v.cal_dir = (rt_uint8_t)(pos % UI_DIRS);
}

static void on_key(rt_uint8_t key)
{
    if (v.view != VIEW_PWD)
        return;
    if (key == 11) {
        v.view = VIEW_MAIN;
    } else if (key == 10) {
        if (v.pin_len)
            v.pin_len--;
    } else if (key <= 9 && v.pin_len < 4) {
        v.pin[v.pin_len++] = (char)('0' + key);
        if (v.pin_len == 4) {
            if (!memcmp(v.pin, s_pin, 4))
                v.view = VIEW_JOG;
            else
                LOG_W("wrong maintenance PIN");
            v.pin_len = 0;
        }
    }
}

static void on_event(const struct hmi_rx_msg *m, const struct ui_state *s)
{
    rt_tick_t now = rt_tick_get();

    if (m->cmd == HMI_EVT_HEARTBEAT) {
        v.t_heartbeat = now;
        if (!v.online) {
            v.online = 1;
            LOG_I("screen online");
        }
        if (m->p1 != v.page)
            v.page = 0xFF;              /* screen is not where we think: redraw */
        return;
    }

    v.t_activity = now;
    if (v.idle) {                       /* any touch wakes the screen and is consumed */
        v.idle = 0;
        return;
    }

    switch (m->cmd) {
    case HMI_EVT_LAYER:
        if (s->phase == UI_PH_READY && m->p1 >= 1 && m->p1 <= s->layers)
            v.layer = m->p1;
        break;
    case HMI_EVT_BAY:
        if (s->phase == UI_PH_READY && v.view == VIEW_MAIN && m->p1 < UI_DIRS &&
            m->p1 != UI_DIR_DOCK && s->bay[v.layer - 1][m->p1] == UI_BAY_CAR) {
            if (v.sel_dir == m->p1 && v.sel_layer == v.layer) {
                sel_clear();
            } else {
                v.sel_layer = (rt_int8_t)v.layer;
                v.sel_dir = (rt_int8_t)m->p1;
            }
        }
        break;
    case HMI_EVT_STORE:
        if (s->phase == UI_PH_READY) {
            sel_clear();
            post(UI_CMD_STORE, 0, 0, 0);
        }
        break;
    case HMI_EVT_RETRIEVE:
        if (s->phase == UI_PH_READY && v.sel_dir >= 0) {
            post(UI_CMD_RETRIEVE, (rt_uint8_t)v.sel_layer, (rt_uint8_t)v.sel_dir, 0);
            sel_clear();
        }
        break;
    case HMI_EVT_CONFIRM_PUT:
        if (s->phase == UI_PH_DOCK_PUT && !(s->sensors & UI_SEN_DOCK_IR))
            post(UI_CMD_CONFIRM_PUT, 0, 0, 0);
        break;
    case HMI_EVT_CANCEL:
        if (s->phase == UI_PH_DOCK_PUT)
            post(UI_CMD_CANCEL, 0, 0, 0);
        break;
    case HMI_EVT_TAKEN:
        if (s->phase == UI_PH_DOCK_TAKE && !(s->sensors & UI_SEN_DOCK_IR))
            post(UI_CMD_TAKEN, 0, 0, 0);
        break;
    case HMI_EVT_TITLE:
        v.title_down = m->p1 ? 1 : 0;
        v.t_title = now;
        break;
    case HMI_EVT_WAKE:
        break;
    case HMI_EVT_FAULT_CHK:
        if (s->phase == UI_PH_FAULT && m->p1 < 2)
            v.chk ^= (rt_uint8_t)(1u << m->p1);
        break;
    case HMI_EVT_FAULT_HOME:
        if (s->phase == UI_PH_FAULT && v.chk == 3) {
            post(UI_CMD_FAULT_ACK, 0, 0, 0);
            v.chk = 0;
        }
        break;
    case HMI_EVT_KEY:
        on_key(m->p1);
        break;
    case HMI_EVT_MT_TAB:
        if (v.view >= VIEW_JOG) {
            static const rt_uint8_t map[4] = { VIEW_JOG, VIEW_CAL, VIEW_SEN, VIEW_MAIN };
            if (m->p1 < 4)
                v.view = map[m->p1];
        }
        break;
    case HMI_EVT_JOG:
        if (v.view == VIEW_JOG && m->p1 < UI_AXIS__COUNT)
            post(UI_CMD_JOG, m->p1, 0, m->p2 ? k_jog_steps[v.jog_step] : -k_jog_steps[v.jog_step]);
        break;
    case HMI_EVT_JOG_STEP:
        if (m->p1 < 3)
            v.jog_step = m->p1;
        break;
    case HMI_EVT_HOME_ALL:
        if (v.view == VIEW_JOG)
            post(UI_CMD_HOME_ALL, 0, 0, 0);
        break;
    case HMI_EVT_CAL_NAV:
        if (v.view == VIEW_CAL)
            cal_step(s, m->p1 != 0);
        break;
    case HMI_EVT_CAL_SAVE:
        if (v.view == VIEW_CAL)
            post(UI_CMD_CAL_SAVE, v.cal_layer, v.cal_dir, 0);
        break;
    default:
        LOG_D("unknown event 0x%02x", m->cmd);
        break;
    }
}

static void on_native(const struct hmi_rx_msg *m)
{
    if (m->cmd == TJC_RET_READY || m->cmd == TJC_RET_STARTUP) {
        LOG_I("screen restarted, redrawing");
        v.page = 0xFF;
        s_shadow[SH_DIM] = SH_INVALID;
    } else if (m->cmd >= TJC_RET_ERR_FIRST && m->cmd <= TJC_RET_ERR_LAST) {
        /* Usually a control name or picture id that does not exist in the HMI project. */
        LOG_W("screen rejected an instruction, code 0x%02x (page %d)", m->cmd, v.page);
    }
}

/* -------------------------------------------------------------- tick */

static void tick(const struct ui_state *s)
{
    rt_tick_t now = rt_tick_get();
    rt_uint8_t page;

    if (++v.blink_cnt >= HMI_BLINK_TICKS) {
        v.blink_cnt = 0;
        v.blink ^= 1;
    }
    if (v.online && now - v.t_heartbeat > rt_tick_from_millisecond(HMI_OFFLINE_MS)) {
        v.online = 0;
        LOG_W("screen offline (no heartbeat)");
    }

    /* View state that must follow the machine state. */
    if (s->phase != UI_PH_FAULT)
        v.chk = 0;
    if (v.sel_dir >= 0 && (s->phase != UI_PH_READY || v.sel_layer > s->layers ||
                           s->bay[v.sel_layer - 1][v.sel_dir] != UI_BAY_CAR))
        sel_clear();
    if (v.cal_layer < 1 || v.cal_layer > s->layers) {
        v.cal_layer = 1;
        v.cal_dir = UI_DIR_E;
    }
    if (v.title_down && v.view == VIEW_MAIN && s->phase == UI_PH_READY && !v.idle &&
        now - v.t_title >= rt_tick_from_millisecond(HMI_TITLE_HOLD_MS)) {
        v.title_down = 0;
        v.view = VIEW_PWD;
        v.pin_len = 0;
    }

    /* Which page should be on screen. */
    if (s->phase == UI_PH_ESTOP || s->phase == UI_PH_FAULT || s->phase == UI_PH_BOOT) {
        v.view = VIEW_MAIN;
        v.idle = 0;
        v.t_activity = now;
        page = s->phase == UI_PH_ESTOP ? HMI_PG_ESTOP :
               s->phase == UI_PH_FAULT ? HMI_PG_FAULT : HMI_PG_BOOT;
    } else if (v.view != VIEW_MAIN) {
        if (s->phase == UI_PH_DOCK_PUT || s->phase == UI_PH_DOCK_TAKE)
            v.view = VIEW_MAIN;         /* a user is at the dock: leave maintenance */
        v.t_activity = now;
        page = v.view == VIEW_PWD ? HMI_PG_PWD : v.view == VIEW_JOG ? HMI_PG_JOG :
               v.view == VIEW_CAL ? HMI_PG_CAL : v.view == VIEW_SEN ? HMI_PG_SEN : HMI_PG_MAIN;
    } else {
        if (s->phase != UI_PH_READY) {
            v.idle = 0;
            v.t_activity = now;
        } else if (now - v.t_activity > rt_tick_from_millisecond(HMI_IDLE_MS)) {
            v.idle = 1;
        }
        page = v.idle ? HMI_PG_IDLE : HMI_PG_MAIN;
    }

    goto_page(page);
    set_dim(page == HMI_PG_IDLE ? HMI_DIM_IDLE : HMI_DIM_ACTIVE);

    switch (page) {
    case HMI_PG_MAIN:  push_main(s);  break;
    case HMI_PG_FAULT: push_fault(s); break;
    case HMI_PG_IDLE:  push_idle(s);  break;
    case HMI_PG_PWD:   push_pwd();    break;
    case HMI_PG_JOG:   push_jog(s);   break;
    case HMI_PG_CAL:   push_cal(s);   break;
    case HMI_PG_SEN:   push_sen(s);   break;
    default: break;                     /* boot and e-stop pages are static */
    }
}

/* ------------------------------------------------------------ thread */

static rt_err_t rx_ind(rt_device_t dev, rt_size_t size)
{
    RT_UNUSED(dev);
    RT_UNUSED(size);
    rt_sem_release(&s_rx_sem);
    return RT_EOK;
}

static void hmi_thread(void *arg)
{
    struct ui_state st;
    struct hmi_rx_msg msg;
    rt_tick_t next = rt_tick_get();
    rt_uint8_t ch;

    RT_UNUSED(arg);
    for (;;) {
        rt_int32_t wait = (rt_int32_t)(next - rt_tick_get());
        int got = 0;

        if (wait > 0)
            rt_sem_take(&s_rx_sem, wait);

        garage_ui_get_state(&st);
        if (st.layers < 1 || st.layers > UI_LAYERS_MAX)
            st.layers = 1;
        while (rt_device_read(s_dev, 0, &ch, 1) == 1) {
            got = 1;
            if (hmi_parser_feed(&s_parser, ch, &msg)) {
                if (msg.kind == HMI_RX_EVENT)
                    on_event(&msg, &st);
                else
                    on_native(&msg);
            }
        }

        if ((rt_int32_t)(rt_tick_get() - next) >= 0) {
            /* A frame cut off for a whole tick will never complete: drop it. */
            if (!got)
                s_parser.len = 0;
            next += rt_tick_from_millisecond(HMI_TICK_MS);
            if ((rt_int32_t)(rt_tick_get() - next) > 0)
                next = rt_tick_get() + rt_tick_from_millisecond(HMI_TICK_MS);
            tick(&st);
        }
    }
}

int hmi_tjc_init(void)
{
    struct serial_configure cfg = RT_SERIAL_CONFIG_DEFAULT;
    rt_thread_t tid;

    s_dev = rt_device_find(HMI_UART_NAME);
    if (!s_dev) {
        LOG_E("%s not found: enable BSP_USING_UART3", HMI_UART_NAME);
        return -RT_ERROR;
    }
    cfg.baud_rate = HMI_BAUD;
    rt_device_control(s_dev, RT_DEVICE_CTRL_CONFIG, &cfg);
    rt_sem_init(&s_rx_sem, "hmi_rx", 0, RT_IPC_FLAG_FIFO);
    if (rt_device_open(s_dev, RT_DEVICE_FLAG_INT_RX) != RT_EOK) {
        LOG_E("open %s failed", HMI_UART_NAME);
        return -RT_ERROR;
    }
    rt_device_set_rx_indicate(s_dev, rx_ind);

    hmi_parser_init(&s_parser);
    rt_memset(&v, 0, sizeof(v));
    v.page = 0xFF;
    v.panel = PM_NONE;
    v.layer = 1;
    v.cal_layer = 1;
    v.jog_step = 1;
    sel_clear();
    v.t_activity = rt_tick_get();
    shadow_reset();
    s_shadow[SH_DIM] = SH_INVALID;

    tid = rt_thread_create("hmi", hmi_thread, RT_NULL, 2048, 20, 10);
    if (!tid)
        return -RT_ENOMEM;
    rt_thread_startup(tid);
    return RT_EOK;
}
INIT_APP_EXPORT(hmi_tjc_init);

/* --------------------------------------------------------------- msh */

#ifdef RT_USING_FINSH
#include <finsh.h>

static int hmi_pin(int argc, char **argv)
{
    int i;

    if (argc != 2 || strlen(argv[1]) != 4) {
        rt_kprintf("usage: hmi_pin <4 digits>\n");
        return -1;
    }
    for (i = 0; i < 4; i++) {
        if (argv[1][i] < '0' || argv[1][i] > '9') {
            rt_kprintf("digits only\n");
            return -1;
        }
    }
    memcpy(s_pin, argv[1], 4);
    rt_kprintf("maintenance PIN changed (kept in RAM until reset)\n");
    return 0;
}
MSH_CMD_EXPORT(hmi_pin, set the screen maintenance PIN);

static int hmi_stat(int argc, char **argv)
{
    RT_UNUSED(argc);
    RT_UNUSED(argv);
    rt_kprintf("screen %s, page %d, view %d, dropped frames %u\n",
               v.online ? "online" : "offline", v.page, v.view, (unsigned)s_parser.bad);
    return 0;
}
MSH_CMD_EXPORT(hmi_stat, show serial screen link status);
#endif
