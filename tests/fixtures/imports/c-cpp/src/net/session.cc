// Implementation of session.hh.
//
// It deliberately does NOT include its own header. The edge
// src/net/session.cc -> src/net/session.hh must come from the
// same-directory, same-stem header pair, which is the one rule in the
// extractor that produces an edge no line of source states. Everywhere
// else in this fixture a pair is also written as an explicit include, so
// a broken pairing rule would go unnoticed. Here it cannot.
//
// This is also why src/net is not in CMakeLists.txt: the file is a
// resolver fixture, not a translation unit.

#include "./config.h"   // -> src/net/config.h; the "./" normalizes away

/* A vendor drop left this stale path behind. From src/net the three ".."
 * segments pop net, then src, then try to pop the repo root itself, so
 * the path is rejected outright. A resolver that clamps ".." at the root
 * instead turns it into include/app/log.h, a file that really exists, and
 * reports a dependency the compiler never had. */
#include "../../../include/app/log.h"

// The glob below spells a block-comment opener inside a string literal.
// A scanner that tracks /* without tracking quote state opens a comment
// here that never closes, and every include after this line disappears
// from the graph with no error anywhere.
static const char *kIgnoreGlob = "/*";

// Placed after that string on purpose: it is the include the trap above
// would swallow.
#include "util/string.h"  // replaced #include "util/strbuf.h"

namespace app {

Session::Session(const net_config &cfg) : store_(nullptr) {
  (void)cfg;
  (void)kIgnoreGlob;
}

Session::~Session() = default;

}  // namespace app
