/* Private network configuration.
 *
 * The basename collides with include/app/config.h on purpose. From inside
 * src/net, "config.h" means THIS file; from src/, "app/config.h" means the
 * public one. A resolver that matches on basename alone has two candidates
 * and no way to choose between them. */
#ifndef CKDEMO_NET_CONFIG_H
#define CKDEMO_NET_CONFIG_H

#include <stddef.h>

/* Climb to the repo root and come back down. Two ".." segments, both
 * legal, and the normalized result stays inside the tree:
 * src/net + ../../ -> the root, + include/app/config.h. */
#include "../../include/app/config.h"

/* Whitespace between the # and the directive name is legal C. It is still
 * an include and must still be matched. */
#  include "../util/strbuf.h"

/* A computed include. The directive names a macro, not a path, and the
 * line that does carry the path is a #define, not an include. The
 * dependency on include/app/log.h is real, and dropping it is the only
 * honest outcome: resolving it means evaluating the preprocessor. */
#define NETCFG_LOG_HEADER "app/log.h"
#include NETCFG_LOG_HEADER

typedef struct net_config {
  size_t timeout_ms;
  int    retries;
} net_config;

#endif /* CKDEMO_NET_CONFIG_H */
