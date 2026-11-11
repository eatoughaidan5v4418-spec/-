/* Minimal RT-Thread stand-in so hmi_tjc.c and ui_sim.c can run on a PC (tools/test_hmi_backend.c). */
#ifndef HOST_RTTHREAD_H
#define HOST_RTTHREAD_H
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

typedef int32_t rt_int32_t;
typedef uint32_t rt_uint32_t;
typedef uint16_t rt_uint16_t;
typedef uint8_t rt_uint8_t;
typedef int8_t rt_int8_t;
typedef uint32_t rt_tick_t;
typedef long rt_base_t;
typedef long rt_err_t;
typedef size_t rt_size_t;
typedef struct rt_device *rt_device_t;
typedef struct rt_thread *rt_thread_t;
struct rt_semaphore { int dummy; };

#define RT_NULL 0
#define RT_EOK 0
#define RT_ERROR 1
#define RT_ENOMEM 5
#define RT_IPC_FLAG_FIFO 0
#define RT_UNUSED(x) ((void)(x))
#define RT_USING_FINSH
#define INIT_APP_EXPORT(fn)
#define MSH_CMD_EXPORT(fn, desc)

extern rt_tick_t host_tick;                 /* 1 tick = 1 ms */
#define rt_tick_get() (host_tick)
#define rt_tick_from_millisecond(ms) ((rt_tick_t)(ms))
#define rt_vsnprintf vsnprintf
#define rt_snprintf snprintf
#define rt_memset memset
#define rt_memcpy memcpy
#define rt_kprintf printf

rt_device_t rt_device_find(const char *name);
rt_size_t rt_device_write(rt_device_t dev, long pos, const void *buf, rt_size_t size);
rt_size_t rt_device_read(rt_device_t dev, long pos, void *buf, rt_size_t size);
#define rt_device_control(d, c, a) ((void)(a))
#define rt_device_open(d, f) (RT_EOK)
#define rt_device_set_rx_indicate(d, cb) ((void)(cb))
#define rt_sem_init(s, n, v, f) ((void)(s))
#define rt_sem_take(s, t) ((void)(t))
#define rt_sem_release(s) ((void)(s))
#define rt_thread_create(n, e, a, st, p, t) (((void)(e)), (rt_thread_t)1)
#define rt_thread_startup(t) ((void)(t))
#define rt_hw_interrupt_disable() (0)
#define rt_hw_interrupt_enable(l) ((void)(l))
#endif
