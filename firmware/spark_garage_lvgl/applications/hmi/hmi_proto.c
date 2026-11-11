/*
 * hmi_proto.c - frame parser for the TJC serial screen link. See hmi_proto.h.
 */
#include "hmi_proto.h"

void hmi_parser_init(struct hmi_parser *p)
{
    p->len = 0;
    p->ff = 0;
    p->bad = 0;
}

static int finish_event(struct hmi_parser *p, struct hmi_rx_msg *out)
{
    const uint8_t *b = p->buf;
    uint8_t sum = (uint8_t)(b[1] + b[2] + b[3]);
    int ok = (b[5] == HMI_EOF) && (b[4] == sum);

    p->len = 0;
    if (!ok) {
        p->bad++;
        return 0;
    }
    out->kind = HMI_RX_EVENT;
    out->cmd = b[1];
    out->p1 = b[2];
    out->p2 = b[3];
    return 1;
}

int hmi_parser_feed(struct hmi_parser *p, uint8_t byte, struct hmi_rx_msg *out)
{
    /* Event frame in progress: fixed length, payload may contain any value. */
    if (p->len > 0 && p->buf[0] == HMI_SOF) {
        p->buf[p->len++] = byte;
        if (p->len == HMI_FRAME_LEN)
            return finish_event(p, out);
        return 0;
    }

    if (p->len == 0) {
        if (byte == 0xFF)           /* stray terminator between frames */
            return 0;
        p->buf[0] = byte;
        p->len = 1;
        p->ff = 0;
        return 0;
    }

    /* Native TJC return: collect until FF FF FF. */
    if (byte == 0xFF) {
        if (++p->ff == 3) {
            out->kind = HMI_RX_NATIVE;
            out->cmd = p->buf[0];
            out->p1 = p->len > 1 ? p->buf[1] : 0;
            out->p2 = p->len > 2 ? p->buf[2] : 0;
            p->len = 0;
            p->ff = 0;
            return 1;
        }
        return 0;
    }
    /* A data byte after one or two FF: those FF were data too. Only the head is kept. */
    p->ff = 0;
    if (p->len < sizeof(p->buf)) {
        p->buf[p->len++] = byte;
    } else {
        /* Too long to be anything we expect: resynchronise. */
        p->bad++;
        p->len = 0;
        if (byte == HMI_SOF) {
            p->buf[0] = byte;
            p->len = 1;
        }
    }
    return 0;
}

void hmi_build_event(uint8_t out[HMI_FRAME_LEN], uint8_t cmd, uint8_t p1, uint8_t p2)
{
    out[0] = HMI_SOF;
    out[1] = cmd;
    out[2] = p1;
    out[3] = p2;
    out[4] = (uint8_t)(cmd + p1 + p2);
    out[5] = HMI_EOF;
}

size_t hmi_terminate(char *buf, size_t len, size_t cap)
{
    if (len + 3 > cap)
        return 0;
    buf[len] = (char)0xFF;
    buf[len + 1] = (char)0xFF;
    buf[len + 2] = (char)0xFF;
    return len + 3;
}
