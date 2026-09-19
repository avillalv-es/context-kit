// The session header. .hh paired with .cc is the extension combination
// nothing else in this fixture exercises, and it pairs by stem exactly
// the way .hpp and .cpp do.
#ifndef CKDEMO_NET_SESSION_HH
#define CKDEMO_NET_SESSION_HH

#include <cstdint>        // C++ standard header, no extension, no repo file

#include "config.h"       // -> src/net/config.h, the file beside this one.
                          // NOT include/app/config.h: same basename, and
                          // the directory-relative hit is the only correct
                          // answer a resolver can give here.
#include "store/store.h"  // -> src/store/store.h through the src/ root.
                          // src/net/store/store.h does not exist, so this
                          // is the one include in the fixture that only a
                          // root fallback can resolve.

namespace app {

class Session {
 public:
  explicit Session(const net_config &cfg);
  ~Session();

 private:
  store *store_;
};

}  // namespace app

#endif  // CKDEMO_NET_SESSION_HH
