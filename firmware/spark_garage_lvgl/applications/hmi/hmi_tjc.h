#ifndef HMI_TJC_H
#define HMI_TJC_H

/*
 * While the scheduler does not exist yet, ui_sim.c provides a fake garage so
 * the screen can be developed and demonstrated on its own. Remove this define
 * (or the file) once the real core implements the functions in ui_model.h.
 */
#define HMI_USING_SIM

/* Opens USART3 and starts the "hmi" thread. Called automatically at start-up. */
int hmi_tjc_init(void);

#endif /* HMI_TJC_H */
