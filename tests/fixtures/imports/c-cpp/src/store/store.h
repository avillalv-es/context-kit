/* Private header. Pairs with store.c, which sits beside it. */
#ifndef CKDEMO_STORE_H
#define CKDEMO_STORE_H

#include <stddef.h>
#include "app/config.h"   /* -> include/app/config.h, rooted from a nested dir */

typedef struct store store;

store *store_open(const app_config *cfg);
store *store_open_memory(size_t cap);
void   store_close(store *s);

#endif /* CKDEMO_STORE_H */
