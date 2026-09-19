/* Leaf header: depends on nothing this repo owns. */
#ifndef APP_LOG_H
#define APP_LOG_H

#include <stdarg.h>

void app_log(const char *fmt, ...);
void app_vlog(const char *fmt, va_list ap);

#endif /* APP_LOG_H */
