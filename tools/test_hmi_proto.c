/*
 * Host unit test for the serial screen frame parser.
 * Build and run from the repository root:
 *   gcc -Wall -Wextra -I firmware/spark_garage_lvgl/applications/hmi \
 *       tools/test_hmi_proto.c firmware/spark_garage_lvgl/applications/hmi/hmi_proto.c \
 *       -o build_test_hmi && ./build_test_hmi
 */
#include <stdio.h>
#include <string.h>
#include "hmi_proto.h"

static int g_fail, g_checks;
#define CHECK(c) do { g_checks++; if (!(c)) { g_fail++; printf("FAIL line %d: %s\n", __LINE__, #c); } } while (0)

static struct hmi_parser p;
static struct hmi_rx_msg got[16];
static int ngot;

static void feed(const uint8_t *d, size_t n)
{
    struct hmi_rx_msg m;
    size_t i;

    for (i = 0; i < n; i++)
        if (hmi_parser_feed(&p, d[i], &m) && ngot < 16)
            got[ngot++] = m;
}

static void reset(void)
{
    hmi_parser_init(&p);
    ngot = 0;
}

int main(void)
{
    uint8_t f[HMI_FRAME_LEN];
    char buf[16];

    /* 1. plain event frame */
    reset();
    hmi_build_event(f, HMI_EVT_BAY, 3, 0);
    CHECK(f[0] == 0xA5 && f[4] == (uint8_t)(0x11 + 3) && f[5] == 0x5A);
    feed(f, sizeof(f));
    CHECK(ngot == 1 && got[0].kind == HMI_RX_EVENT && got[0].cmd == HMI_EVT_BAY && got[0].p1 == 3);

    /* 2. payload bytes equal to SOF / EOF / FF must not confuse the parser */
    reset();
    hmi_build_event(f, HMI_EVT_JOG, 0xA5, 0xFF);
    feed(f, sizeof(f));
    hmi_build_event(f, HMI_EVT_KEY, 0x5A, 0);
    feed(f, sizeof(f));
    CHECK(ngot == 2 && got[0].p1 == 0xA5 && got[0].p2 == 0xFF && got[1].p1 == 0x5A);

    /* 3. bad checksum is dropped and counted, next frame still parses */
    reset();
    hmi_build_event(f, HMI_EVT_STORE, 0, 0);
    f[4] ^= 0x01;
    feed(f, sizeof(f));
    CHECK(ngot == 0 && p.bad == 1);
    hmi_build_event(f, HMI_EVT_STORE, 0, 0);
    feed(f, sizeof(f));
    CHECK(ngot == 1 && got[0].cmd == HMI_EVT_STORE);

    /* 4. bad tail */
    reset();
    hmi_build_event(f, HMI_EVT_TAKEN, 0, 0);
    f[5] = 0x00;
    feed(f, sizeof(f));
    CHECK(ngot == 0 && p.bad == 1);

    /* 5. TJC native returns: ready, start-up, instruction error */
    reset();
    feed((const uint8_t *)"\x88\xFF\xFF\xFF", 4);
    feed((const uint8_t *)"\x00\x00\x00\xFF\xFF\xFF", 6);
    feed((const uint8_t *)"\x1A\xFF\xFF\xFF", 4);
    CHECK(ngot == 3);
    CHECK(got[0].kind == HMI_RX_NATIVE && got[0].cmd == TJC_RET_READY);
    CHECK(got[1].kind == HMI_RX_NATIVE && got[1].cmd == TJC_RET_STARTUP);
    CHECK(got[2].kind == HMI_RX_NATIVE && got[2].cmd == 0x1A);

    /* 6. native and event frames back to back, plus stray FF between them */
    reset();
    feed((const uint8_t *)"\xFF\xFF\x88\xFF\xFF\xFF\xFF", 7);
    hmi_build_event(f, HMI_EVT_HEARTBEAT, 1, 0);
    feed(f, sizeof(f));
    feed((const uint8_t *)"\x1A\xFF\xFF\xFF", 4);
    CHECK(ngot == 3 && got[1].kind == HMI_RX_EVENT && got[1].cmd == HMI_EVT_HEARTBEAT && got[1].p1 == 1);

    /* 7. touch return 0x65 (if someone leaves "send component id" ticked) is one native message */
    reset();
    feed((const uint8_t *)"\x65\x01\x04\x01\xFF\xFF\xFF", 7);
    CHECK(ngot == 1 && got[0].kind == HMI_RX_NATIVE && got[0].cmd == 0x65 && got[0].p1 == 1 && got[0].p2 == 4);

    /* 8. long garbage resynchronises and does not block later frames for ever */
    reset();
    {
        uint8_t junk[40];
        memset(junk, 0x33, sizeof(junk));
        feed(junk, sizeof(junk));
        feed((const uint8_t *)"\xFF\xFF\xFF", 3);
        ngot = 0;
        hmi_build_event(f, HMI_EVT_WAKE, 0, 0);
        feed(f, sizeof(f));
        CHECK(ngot == 1 && got[0].cmd == HMI_EVT_WAKE && p.bad > 0);
    }

    /* 9. terminator helper and colour macro */
    memcpy(buf, "page 1", 6);
    CHECK(hmi_terminate(buf, 6, sizeof(buf)) == 9 && (uint8_t)buf[6] == 0xFF && (uint8_t)buf[8] == 0xFF);
    CHECK(hmi_terminate(buf, 14, sizeof(buf)) == 0);
    CHECK(HMI_RGB565(0xFF, 0xFF, 0xFF) == 0xFFFF && HMI_RGB565(0xFF, 0, 0) == 0xF800 &&
          HMI_RGB565(0, 0xFF, 0) == 0x07E0 && HMI_RGB565(0, 0, 0xFF) == 0x001F);

    printf("%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
