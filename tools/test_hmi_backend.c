/*
 * Host scenario test for the serial screen backend (hmi_tjc.c) running against
 * the fake garage (ui_sim.c). RT-Thread is replaced by tools/hmi_host_shim.
 * It checks which instructions would be sent to the screen; it cannot check
 * how the real screen renders them.
 *
 * Build and run from the repository root:
 *   gcc -Wall -I tools/hmi_host_shim -I firmware/spark_garage_lvgl/applications/hmi \
 *       tools/test_hmi_backend.c firmware/spark_garage_lvgl/applications/hmi/hmi_proto.c \
 *       -o build_test_backend && ./build_test_backend
 */
#include "rtthread.h"

rt_tick_t host_tick;
static char g_tx[8192];
static size_t g_tx_len;
static int g_cmds;

rt_device_t rt_device_find(const char *name)
{
    return strcmp(name, "uart3") ? RT_NULL : (rt_device_t)1;    /* no RTC on the host */
}

/* Record every instruction as one text line, terminator stripped. */
rt_size_t rt_device_write(rt_device_t dev, long pos, const void *buf, rt_size_t size)
{
    (void)dev; (void)pos;
    if (size >= 3 && g_tx_len + size < sizeof(g_tx)) {
        memcpy(g_tx + g_tx_len, buf, size - 3);
        g_tx_len += size - 3;
        g_tx[g_tx_len++] = '\n';
        g_tx[g_tx_len] = 0;
        g_cmds++;
    }
    return size;
}

rt_size_t rt_device_read(rt_device_t dev, long pos, void *buf, rt_size_t size)
{
    (void)dev; (void)pos; (void)buf; (void)size;
    return 0;
}

#include "../firmware/spark_garage_lvgl/applications/hmi/hmi_tjc.c"
#include "../firmware/spark_garage_lvgl/applications/hmi/ui_sim.c"

static int g_fail, g_checks;
#define CHECK(c) do { g_checks++; if (!(c)) { g_fail++; printf("FAIL line %d: %s\n--- sent ---\n%s------------\n", __LINE__, #c, g_tx); } } while (0)

static void clear(void) { g_tx_len = 0; g_tx[0] = 0; g_cmds = 0; }
static int sent(const char *line)
{
    char pat[160];
    snprintf(pat, sizeof(pat), "%s\n", line);
    return strstr(g_tx, pat) == g_tx || (snprintf(pat, sizeof(pat), "\n%s\n", line), strstr(g_tx, pat) != NULL);
}

/* Advance time in 100 ms backend ticks. */
static void run(int ms)
{
    struct ui_state st;
    for (; ms > 0; ms -= HMI_TICK_MS) {
        host_tick += HMI_TICK_MS;
        garage_ui_get_state(&st);
        tick(&st);
    }
}

static void ev(uint8_t cmd, uint8_t p1, uint8_t p2)
{
    struct ui_state st;
    struct hmi_rx_msg m = { HMI_RX_EVENT, cmd, p1, p2 };
    garage_ui_get_state(&st);
    on_event(&m, &st);
}

int main(void)
{
    char *argv_f[] = { "sim_fault", "12" };
    char *argv_e1[] = { "sim_estop", "1" }, *argv_e0[] = { "sim_estop", "0" };
    int i;

    CHECK(hmi_tjc_init() == RT_EOK);

    /* boot page first, then the main page with the home panel */
    run(100);
    CHECK(sent("page 0") && sent("dim=100"));
    clear();
    run(2200);
    CHECK(sent("page 1") && sent("pPanel.pic=3"));
    CHECK(sent("b0.pic=10"));                       /* E: car */
    CHECK(sent("b1.pic=14"));                       /* NE: tray */
    CHECK(sent("b6.pic=39"));                       /* S on 1F: dock with tray */
    CHECK(sent("hub.pic=54"));                      /* heading south */
    CHECK(sent("nFree.val=10") && sent("tTot.txt=\"/ 14\"") && sent("jOcc.val=29"));
    CHECK(sent("jOcc.bpic=85") && sent("tab1.pic=57") && sent("tab2.pic=60"));
    CHECK(sent("tClk.txt=\"--:--\""));
    CHECK(sent("bStore.pic=61") && sent("tsw bStore,1"));
    CHECK(!sent("vis bStore,0\nvis bStore,0"));

    /* nothing changes -> nothing is sent */
    clear();
    run(1000);
    CHECK(g_cmds == 0);

    /* layer tab */
    ev(HMI_EVT_LAYER, 2, 0);
    run(100);
    CHECK(sent("tab1.pic=58") && sent("tab2.pic=59"));
    CHECK(sent("b6.pic=41"));                       /* 2F south: shaft */
    CHECK(sent("b0.pic=9") && sent("hub.pic=56"));  /* 2F east: tray; carriage is on 1F */
    CHECK(!sent("b2.pic=20"));                      /* N is a car on both layers: unchanged */
    ev(HMI_EVT_LAYER, 1, 0);
    run(100);

    /* tapping a tray bay does nothing; tapping a car selects it */
    clear();
    ev(HMI_EVT_BAY, UI_DIR_NE, 0);
    run(100);
    CHECK(g_cmds == 0);
    ev(HMI_EVT_BAY, UI_DIR_N, 0);
    run(100);
    CHECK(sent("pPanel.pic=4") && sent("b2.pic=21") && sent("vis bGet,1") && sent("vis bStore,0"));
    CHECK(strstr(g_tx, "pPanel.pic=4") < strstr(g_tx, "vis tab1,1"));   /* tabs are redrawn over the new panel */
    CHECK(strstr(g_tx, "tSel.txt=\"1F \xA1\xA4 \xB1\xB1\"") != NULL);     /* "1F · 北" in GB2312 */

    /* retrieve: progress panel, target blinks, ends at the dock */
    clear();
    ev(HMI_EVT_RETRIEVE, 0, 0);
    run(100);
    CHECK(sent("pPanel.pic=7") && sent("tIdx.txt=\"1 / 5\"") && sent("jStep.val=20") && sent("nEta.val=10"));
    clear();
    run(1000);
    CHECK(sent("b2.pic=22") && sent("b2.pic=20"));  /* target <-> car, 2 Hz */
    clear();
    run(9500);
    CHECK(sent("hub.pic=50"));                      /* rotated to north on the way */
    CHECK(sent("pPanel.pic=6") && sent("b6.pic=40") && sent("b2.pic=19"));
    CHECK(sent("pHand.pic=77") && sent("bTaken.pic=73") && sent("tsw bTaken,0"));
    CHECK(sent("vis bTaken,1") && !sent("vis bOk,1"));
    /* a press while the beam is blocked is ignored */
    ev(HMI_EVT_TAKEN, 0, 0);
    clear();
    run(2000);
    CHECK(sent("pHand.pic=76") && sent("bTaken.pic=71") && sent("tsw bTaken,1"));
    CHECK(!sent("pPanel.pic=3"));
    clear();
    ev(HMI_EVT_TAKEN, 0, 0);
    run(100);
    CHECK(sent("pPanel.pic=3") && sent("nFree.val=11") && sent("b6.pic=39"));

    /* store: dock panel, confirm disabled until the beam clears, cancel works */
    clear();
    ev(HMI_EVT_STORE, 0, 0);
    run(100);
    CHECK(sent("pPanel.pic=5") && sent("bOk.pic=68") && sent("vis bCancel,1") && !sent("vis bTaken,1"));
    CHECK(sent("vis tab1,0") && !sent("vis tab1,1"));           /* no layer tabs at the dock */
    ev(HMI_EVT_CANCEL, 0, 0);
    run(100);
    CHECK(sent("pPanel.pic=3"));
    ev(HMI_EVT_STORE, 0, 0);
    run(2500);
    clear();
    ev(HMI_EVT_CONFIRM_PUT, 0, 0);
    run(100);
    CHECK(sent("pPanel.pic=7") && sent("tIdx.txt=\"1 / 6\""));
    run(12500);
    CHECK(sent("pPanel.pic=3") && sent("b1.pic=15") && sent("nFree.val=10"));   /* NE now holds a car */

    /* fault page: both checks are required before re-homing */
    clear();
    sim_fault(2, argv_f);
    run(100);
    CHECK(sent("page 2") && sent("tCode.txt=\"E12\"") && sent("bHome.pic=82") && sent("tsw bHome,0"));
    ev(HMI_EVT_FAULT_HOME, 0, 0);
    ev(HMI_EVT_FAULT_CHK, 0, 0);
    clear();
    run(100);
    CHECK(sent("c0.pic=79") && !sent("tsw bHome,1"));
    ev(HMI_EVT_FAULT_CHK, 1, 0);
    run(100);
    CHECK(sent("c1.pic=81") && sent("bHome.pic=83") && sent("tsw bHome,1"));
    clear();
    ev(HMI_EVT_FAULT_HOME, 0, 0);
    run(100);
    CHECK(sent("page 1") && sent("pPanel.pic=7"));
    run(2500);
    CHECK(sent("pPanel.pic=3"));

    /* emergency stop, then position confirmation (E01) */
    clear();
    sim_estop(2, argv_e1);
    run(100);
    CHECK(sent("page 3"));
    sim_estop(2, argv_e0);
    run(100);
    CHECK(sent("page 2") && sent("tCode.txt=\"E01\"") && sent("c0.pic=78"));
    ev(HMI_EVT_FAULT_CHK, 0, 0);
    ev(HMI_EVT_FAULT_CHK, 1, 0);
    ev(HMI_EVT_FAULT_HOME, 0, 0);
    run(2500);

    /* standby after 60 s, first touch only wakes */
    clear();
    run(59000);
    CHECK(!sent("page 4"));
    run(1500);
    CHECK(sent("page 4") && sent("dim=30") && sent("nFree.val=10"));
    clear();
    ev(HMI_EVT_WAKE, 0, 0);
    run(100);
    CHECK(sent("page 1") && sent("dim=100"));

    /* long press on the title -> PIN page; wrong PIN stays, right PIN enters */
    ev(HMI_EVT_TITLE, 1, 0);
    run(1000);
    ev(HMI_EVT_TITLE, 0, 0);
    clear();
    run(3000);
    CHECK(!sent("page 5"));
    ev(HMI_EVT_TITLE, 1, 0);
    run(3100);
    CHECK(sent("page 5") && sent("d0.pic=91"));
    clear();
    ev(HMI_EVT_KEY, 1, 0);
    ev(HMI_EVT_KEY, 2, 0);
    run(100);
    CHECK(sent("d0.pic=92") && sent("d1.pic=92") && sent("d2.pic=91"));
    ev(HMI_EVT_KEY, 10, 0);
    ev(HMI_EVT_KEY, 3, 0);
    ev(HMI_EVT_KEY, 4, 0);
    ev(HMI_EVT_KEY, 5, 0);                          /* 1345: wrong */
    clear();
    run(100);
    CHECK(!sent("page 6") && sent("d0.pic=91"));
    for (i = 0; i < 4; i++)
        ev(HMI_EVT_KEY, 0, 0);
    run(100);
    CHECK(sent("page 6") && sent("n0.val=0") && sent("s1.bco=9885"));

    /* jog, calibration, sensors */
    clear();
    ev(HMI_EVT_JOG_STEP, 2, 0);
    ev(HMI_EVT_JOG, UI_AXIS_LIFT, 1);
    ev(HMI_EVT_JOG, UI_AXIS_ROTATE, 0);
    run(100);
    CHECK(sent("n0.val=100") && sent("n1.val=-100") && sent("s2.bco=9885") && sent("s1.bco=4326"));
    ev(HMI_EVT_MT_TAB, 1, 0);
    clear();
    run(100);
    CHECK(sent("page 7") && sent("nHc.val=100") && sent("nHs.val=0"));
    ev(HMI_EVT_CAL_SAVE, 0, 0);
    ev(HMI_EVT_CAL_NAV, 0, 0);                      /* back from 1F-E wraps to 2F-SE */
    clear();
    run(100);
    CHECK(strstr(g_tx, "tBay.txt=\"2F ") != NULL && sent("nHs.val=0") == 0);
    ev(HMI_EVT_CAL_NAV, 1, 0);
    run(100);
    CHECK(sent("nHs.val=100") && sent("nAs.val=-100"));
    ev(HMI_EVT_MT_TAB, 2, 0);
    clear();
    run(100);
    CHECK(sent("page 8") && sent("l0.bco=13971") && sent("l10.bco=6440") && sent("l15.bco=13971"));
    ev(HMI_EVT_MT_TAB, 3, 0);
    run(100);
    CHECK(sent("page 1"));

    /* screen reports another page (it restarted): everything is redrawn */
    clear();
    ev(HMI_EVT_HEARTBEAT, 0, 0);
    run(100);
    CHECK(sent("page 1") && sent("pPanel.pic=3") && sent("b0.pic=10"));
    clear();
    ev(HMI_EVT_HEARTBEAT, 1, 0);
    run(300);
    CHECK(g_cmds == 0);

    printf("%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
