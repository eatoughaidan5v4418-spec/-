#ifndef GARAGE_UI_H
#define GARAGE_UI_H

#ifdef __cplusplus
extern "C" {
#endif

/* LVGL thread entry. Called from lv_user_gui_init(), not from main(). */
void garage_ui_init(void);

#ifdef __cplusplus
}
#endif

#endif /* GARAGE_UI_H */
