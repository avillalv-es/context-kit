/* Private header with no implementation file of its own, so nothing pairs
 * with it. */
#ifndef CKDEMO_UTIL_STRBUF_H
#define CKDEMO_UTIL_STRBUF_H

#include <stddef.h>

typedef struct strbuf {
  char  *data;
  size_t len;
  size_t cap;
} strbuf;

int  strbuf_init(strbuf *sb, size_t cap);
void strbuf_free(strbuf *sb);

#endif /* CKDEMO_UTIL_STRBUF_H */
