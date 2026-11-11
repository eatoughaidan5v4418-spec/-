#ifndef HOST_RTDEVICE_H
#define HOST_RTDEVICE_H
struct serial_configure { int baud_rate; };
#define RT_SERIAL_CONFIG_DEFAULT { 0 }
#define BAUD_RATE_115200 115200
#define RT_DEVICE_CTRL_CONFIG 0
#define RT_DEVICE_FLAG_INT_RX 0
#endif
