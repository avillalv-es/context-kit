/* CLI entry point. Compiled with -Iinclude -Isrc, so every internal header
 * is reached by a rooted path and never by climbing out of src/. */

#include <stdio.h>       /* system header: must not resolve to a repo file */
#include <stdlib.h>      /* system header */
#include <curl/curl.h>   /* third-party, not vendored here: must not resolve */

#include "app/config.h"  /* -> include/app/config.h via the include/ root */
#include "app/log.h"     /* -> include/app/log.h */
#include "store/store.h" /* -> src/store/store.h, relative to src/ */

/* An include that used to live here, kept as documentation:
 * #include "util/strbuf.h"
 * The block comment runs across lines, so none of it is code.
 */

/* #include "store/store_mem.c" */   /* single-line block comment */

// #include "engine.hpp"             // commented out while the C++ engine is optional

int main(int argc, char **argv) {
  app_config cfg;
  store *s;

  (void)argc;
  if (app_config_load(&cfg, argv[1]) != 0) {
    app_log("config load failed");
    return 1;
  }
  s = store_open(&cfg);
  return s ? 0 : 1;
}
