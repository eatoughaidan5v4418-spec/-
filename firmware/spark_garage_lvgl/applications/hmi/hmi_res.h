/*
 * hmi_res.h - page ids and picture ids of the TJC HMI project.
 *
 * These numbers are the import order in the USART HMI editor. If a page or a
 * picture is inserted in the middle, renumber here AND in
 * docs/串口屏界面_v1/README.md (sections 3 and 4).
 */
#ifndef HMI_RES_H
#define HMI_RES_H

/* ---- pages ---- */
enum hmi_page {
    HMI_PG_BOOT = 0,
    HMI_PG_MAIN,        /* map + right panel: home / selected / dock / progress */
    HMI_PG_FAULT,
    HMI_PG_ESTOP,
    HMI_PG_IDLE,
    HMI_PG_PWD,
    HMI_PG_JOG,
    HMI_PG_CAL,
    HMI_PG_SEN,
    HMI_PG__COUNT
};

/* ---- pictures ---- */
#define PIC_BG_MAIN         0
#define PIC_BG_FAULT        1
#define PIC_BG_ESTOP        2

#define PIC_PANEL_HOME      3       /* right panel body, 208x240 at (272,32) */
#define PIC_PANEL_SEL       4
#define PIC_PANEL_DOCK_PUT  5
#define PIC_PANEL_DOCK_TAKE 6
#define PIC_PANEL_PROG      7

/* Bay sprites: PIC_BAY_BASE + dir * 5 + state. */
#define PIC_BAY_BASE        8
#define BAY_ST_EMPTY        0
#define BAY_ST_TRAY         1
#define BAY_ST_CAR          2
#define BAY_ST_SEL          3
#define BAY_ST_TARGET       4
/* The south slot reuses indexes 2 and 3 for its own states. */
#define BAY_ST_DOCK_ACTIVE  2
#define BAY_ST_SHAFT        3

#define PIC_HUB_BASE        48      /* + heading 0..7 */
#define PIC_HUB_NONE        56      /* carriage is on another layer */

#define PIC_TAB1_ON         57
#define PIC_TAB1_OFF        58
#define PIC_TAB2_ON         59
#define PIC_TAB2_OFF        60

#define PIC_BTN_STORE       61
#define PIC_BTN_STORE_DOWN  62
#define PIC_BTN_STORE_OFF   63
#define PIC_BTN_GET         64
#define PIC_BTN_GET_DOWN    65
#define PIC_BTN_OK          66
#define PIC_BTN_OK_DOWN     67
#define PIC_BTN_OK_OFF      68
#define PIC_BTN_CANCEL      69
#define PIC_BTN_CANCEL_DOWN 70
#define PIC_BTN_TAKEN       71
#define PIC_BTN_TAKEN_DOWN  72
#define PIC_BTN_TAKEN_OFF   73

#define PIC_ROW_TRAY_OK     74
#define PIC_ROW_TRAY_WAIT   75
#define PIC_ROW_HAND_CLEAR  76
#define PIC_ROW_HAND_BLOCK  77

#define PIC_CHK0_OFF        78
#define PIC_CHK0_ON         79
#define PIC_CHK1_OFF        80
#define PIC_CHK1_ON         81
#define PIC_BTN_HOME_OFF    82
#define PIC_BTN_HOME        83
#define PIC_BTN_HOME_DOWN   84

#define PIC_OCC14_EMPTY     85      /* occupancy bar, 14 segments (two layers) */
#define PIC_OCC14_FULL      86
#define PIC_OCC7_EMPTY      87      /* 7 segments (one layer) */
#define PIC_OCC7_FULL       88
#define PIC_BAR_EMPTY       89      /* step progress bar */
#define PIC_BAR_FULL        90

#define PIC_PIN_EMPTY       91
#define PIC_PIN_FULL        92
#define PIC__COUNT          93

#endif /* HMI_RES_H */
