/*
 * hmi_proto.h - byte protocol between the MCU and the TJC serial screen.
 * Pure C, no RT-Thread dependency, so it can be unit-tested on a PC
 * (tools/test_hmi_proto.c).
 *
 * Screen -> MCU, two kinds of frames share the line:
 *   1. Our event frame, sent by "printh" in touch events, fixed 6 bytes:
 *        A5  CMD  P1  P2  SUM  5A        SUM = (CMD + P1 + P2) & 0xFF
 *   2. TJC native returns, terminated by FF FF FF (0x88 ready, 0x1A error ...).
 *      Native returns never start with 0xA5.
 *
 * MCU -> screen: TJC native instructions in ASCII (text in GB2312) + FF FF FF.
 */
#ifndef HMI_PROTO_H
#define HMI_PROTO_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define HMI_SOF     0xA5
#define HMI_EOF     0x5A
#define HMI_FRAME_LEN 6

/* Event codes (CMD byte). Keep in sync with docs/串口屏界面_v1/README.md section 5. */
enum hmi_evt {
    HMI_EVT_HEARTBEAT   = 0x01,     /* p1 = current page id, every 1 s */

    HMI_EVT_LAYER       = 0x10,     /* p1 = 1 / 2 */
    HMI_EVT_BAY         = 0x11,     /* p1 = dir 0..7 */
    HMI_EVT_STORE       = 0x12,
    HMI_EVT_RETRIEVE    = 0x13,
    HMI_EVT_CONFIRM_PUT = 0x14,
    HMI_EVT_CANCEL      = 0x15,
    HMI_EVT_TAKEN       = 0x16,
    HMI_EVT_TITLE       = 0x17,     /* p1 = 1 pressed, 0 released (long press -> maintenance) */
    HMI_EVT_WAKE        = 0x18,     /* touch on the standby page */

    HMI_EVT_FAULT_CHK   = 0x20,     /* p1 = 0 / 1: which manual check was tapped */
    HMI_EVT_FAULT_HOME  = 0x21,

    HMI_EVT_KEY         = 0x30,     /* p1 = 0..9, 10 = backspace, 11 = close */

    HMI_EVT_MT_TAB      = 0x40,     /* p1 = 0 jog, 1 cal, 2 sensors, 3 exit */
    HMI_EVT_JOG         = 0x41,     /* p1 = axis 0..2, p2 = 0 minus / 1 plus */
    HMI_EVT_JOG_STEP    = 0x42,     /* p1 = 0 / 1 / 2 -> 1 / 10 / 100 steps */
    HMI_EVT_HOME_ALL    = 0x43,
    HMI_EVT_CAL_NAV     = 0x44,     /* p1 = 0 previous bay, 1 next bay */
    HMI_EVT_CAL_SAVE    = 0x45
};

/* TJC native return codes we care about (first byte). */
#define TJC_RET_STARTUP     0x00    /* 00 00 00 FF FF FF after power-on */
#define TJC_RET_READY       0x88    /* 88 FF FF FF: screen finished booting */
#define TJC_RET_ERR_FIRST   0x02    /* 0x02..0x24 with bkcmd=2: instruction failed */
#define TJC_RET_ERR_LAST    0x24

enum hmi_rx_kind { HMI_RX_NONE = 0, HMI_RX_EVENT, HMI_RX_NATIVE };

struct hmi_rx_msg {
    uint8_t kind;           /* enum hmi_rx_kind */
    uint8_t cmd;            /* event code, or first byte of a native return */
    uint8_t p1, p2;         /* event parameters; for native: next two bytes if present */
};

struct hmi_parser {
    uint8_t buf[12];
    uint8_t len;
    uint8_t ff;             /* consecutive 0xFF seen in a native frame */
    uint32_t bad;           /* dropped frames (bad checksum / tail / overflow) */
};

void hmi_parser_init(struct hmi_parser *p);
/* Feed one byte. Returns 1 and fills *out when a complete message is ready. */
int  hmi_parser_feed(struct hmi_parser *p, uint8_t byte, struct hmi_rx_msg *out);

/* Build an event frame (used by the unit test and the PC simulator). */
void hmi_build_event(uint8_t out[HMI_FRAME_LEN], uint8_t cmd, uint8_t p1, uint8_t p2);

/* Append the FF FF FF terminator. Returns total length, or 0 if it does not fit. */
size_t hmi_terminate(char *buf, size_t len, size_t cap);

#define HMI_RGB565(r, g, b) \
    ((uint16_t)((((r) & 0xF8) << 8) | (((g) & 0xFC) << 3) | ((b) >> 3)))

#ifdef __cplusplus
}
#endif

#endif /* HMI_PROTO_H */
