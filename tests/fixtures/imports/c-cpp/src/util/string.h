/* The project string helpers.
 *
 * The basename collides with the C standard <string.h>, which src/config.c
 * includes. Nothing in the text of that include says whether it means the
 * platform header or this one; only the rule does. A resolver that matches
 * a one-segment system header against the file index links src/config.c to
 * this file and is wrong every time. */
#ifndef CKDEMO_UTIL_STRING_H
#define CKDEMO_UTIL_STRING_H

#include <stddef.h>

/* include_next is a DIFFERENT directive. Its whole purpose is to skip the
 * file being compiled and reach the next file of that name further down
 * the search path, so it never names a file in this repo. A pattern loose
 * enough to read "#include_next" as "#include" resolves it against the
 * index and, now that src/util/string.h exists, finds something. */
#include_next <string.h>

char  *ck_strdup(const char *s);
size_t ck_strlcpy(char *dst, const char *src, size_t n);

#endif /* CKDEMO_UTIL_STRING_H */
