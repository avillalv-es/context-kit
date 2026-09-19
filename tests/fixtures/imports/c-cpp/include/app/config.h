/* Public configuration header. Installed, so it includes its siblings by
 * their rooted path rather than by a relative one. */
#ifndef APP_CONFIG_H
#define APP_CONFIG_H

#include <stddef.h>   /* system header: no repo file owns it */
#include "app/log.h"  /* rooted include of a sibling public header */

typedef struct app_config {
  const char *path;
  size_t      cache_bytes;
  int         verbose;
} app_config;

int app_config_load(app_config *cfg, const char *path);

#endif /* APP_CONFIG_H */
