#include "engine.hpp"  // -> src/engine.hpp, same directory (and the pair)
#include "app/log.h"   // -> include/app/log.h

#include "util/memory.hpp"  // -> src/util/memory.hpp, rooted at src/. This
                            // is the repo header that <memory> in
                            // engine.hpp must not be confused with, and it
                            // is deliberately included from HERE so the two
                            // edges cannot mask each other.

#include <cstdio>      // system header
#include <curl/curl.h> // third-party, not vendored here

// #include "store/store_mem.c"   // commented out: an implementation file is
//                                // never included, and this must not edge

/* Migration note, spanning lines on purpose:
 * #include "util/strbuf.h"
 * #include <app/config.h>
 * Neither line is code, so neither becomes an edge.
 */

namespace app {

// The banner text quotes an include so the docs render it verbatim. The
// quoted text is data, not a directive.
static const char *kDocLine =
    "#include \"app/config.h\"";

// The usage banner is a C++11 raw string. Everything between R"( and )"
// is data, including the line below that starts in column 0 and looks
// exactly like a directive. Anchoring the include pattern to the start of
// the line does not help here - only carrying raw-string state across
// lines does. src/store/store.h is a real file, so the invented edge
// looks entirely plausible in the graph.
static const char *kUsageBanner = R"(
usage: ckdemo_cli <config>

to vendor the store into your own build, add this line:
#include "store/store.h"
)";

Engine::Engine(const app_config &cfg)
    : store_(store_open(&cfg), store_close) {
  app_log("engine up: %s", kDocLine);
  (void)kUsageBanner;
  (void)mem_take;
}

Engine::~Engine() = default;

}  // namespace app
