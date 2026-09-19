/* Pairs with store.h by filename, and also includes it explicitly. */

#include "store.h"          /* -> src/store/store.h, same directory */
#include "../util/strbuf.h" /* -> src/util/strbuf.h, relative climb */
#include "app/log.h"        /* -> include/app/log.h via the include/ root */

#include <stdlib.h>
#include "nanopb/pb_encode.h" /* third-party header on the -I path, not in
                               * this repo: quoted, but still unresolvable */

struct store {
  const app_config *cfg;
  strbuf            scratch;
};

store *store_open(const app_config *cfg) {
  store *s = (store *)calloc(1, sizeof(*s));
  if (s == NULL) return NULL;
  s->cfg = cfg;
  if (strbuf_init(&s->scratch, 128) != 0) {
    free(s);
    app_log("scratch alloc failed");
    return NULL;
  }
  return s;
}

void store_close(store *s) {
  if (s == NULL) return;
  strbuf_free(&s->scratch);
  free(s);
}
