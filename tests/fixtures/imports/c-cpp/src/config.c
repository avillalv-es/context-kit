/* Implementation of the public config header. The header lives under
 * include/ and the source under src/, so the two do not pair by filename -
 * the edge below is the only thing that ties them together. */

#include "app/config.h"   /* -> include/app/config.h via the include/ root */
#include "util/strbuf.h"  /* -> src/util/strbuf.h, relative to this file's dir */

#include <stdio.h>
#include <string.h>

int app_config_load(app_config *cfg, const char *path) {
  strbuf sb;

  if (cfg == NULL || path == NULL) return -1;
  if (strbuf_init(&sb, 64) != 0) return -1;

  memset(cfg, 0, sizeof(*cfg));
  cfg->path = path;
  cfg->cache_bytes = 1024;
  strbuf_free(&sb);
  return 0;
}
