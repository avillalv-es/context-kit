// Owning-pointer helpers for the store.
//
// The stem collides with the C++ standard header <memory>, which
// src/engine.hpp includes. <memory> carries no extension, so a resolver
// that appends .h/.hpp/.cpp to an unresolved specifier lands on this file
// and reports the standard library as a dependency of the project.
#pragma once

#include <cstddef>

/* This block comment closes and leaves a live directive behind it on the
 * same physical line. Everything after the close is code, so the include
 * is real and must be found - a scanner that discards the whole line once
 * it sees a comment on it loses a true edge.
 */ #include "strbuf.h"

namespace app {

void *mem_take(void *p);
void  mem_drop(void *p);

}  // namespace app
