// C++ side of the same project. Pairs with engine.cpp.
#pragma once

#include <memory>        // C++ standard header, no extension. src/util/
                         // memory.hpp exists, so appending .hpp to this
                         // specifier reaches a repo file - it must not.
                         // Nothing in this header includes util/memory.hpp,
                         // so ANY edge from engine.hpp to it is invented.
#include <app/config.h>  // angle include of a header this repo DOES own:
                         // it is on the -Iinclude path, so it resolves

#include "store/store.h" // -> src/store/store.h, rooted at src/

namespace app {

class Engine {
 public:
  explicit Engine(const app_config &cfg);
  ~Engine();

 private:
  std::unique_ptr<store, void (*)(store *)> store_;
};

}  // namespace app
