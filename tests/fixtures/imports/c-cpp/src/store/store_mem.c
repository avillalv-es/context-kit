/* In-memory backend. */

#include "store.h"          /* -> src/store/store.h */
#include "../util/strbuf.h" /* -> src/util/strbuf.h */

#include <stdlib.h>

/* A line-continued include. The preprocessor joins the two physical lines,
 * so this is a real dependency on include/app/log.h - but a line matcher
 * sees neither line as an include and emits nothing. Dropping it is the
 * intended behaviour: a missed edge makes you look further, an invented one
 * makes you stop looking. */
#include \
    "app/log.h"

store *store_open_memory(size_t cap) {
  store *s = (store *)calloc(1, sizeof(*s));
  if (s == NULL) return NULL;
  if (strbuf_init(&s->scratch, cap) != 0) {
    free(s);
    return NULL;
  }
  return s;
}
