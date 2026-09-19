# Project metadata. The extractor does not parse this file - it matters
# because it documents the two include roots the fixture assumes:
#
#   include/   the app's public headers, reached as "app/<name>.h"
#   src/       the app's private headers, reached as "store/<name>.h",
#              "util/<name>.h" and "net/<name>.h"
#
# Those are the same two roots the resolver falls back to, which is why a
# rooted include like "app/config.h" resolves without a compile database.
#
# src/net is deliberately NOT built. src/net/session.cc omits the include
# of its own header on purpose, so that the only justification for the
# src/net/session.cc -> src/net/session.hh edge is the same-directory,
# same-stem header pair. That makes it a resolver fixture rather than a
# translation unit.
cmake_minimum_required(VERSION 3.16)
project(ckdemo C CXX)

add_library(ckdemo
  src/config.c
  src/store/store.c
  src/store/store_mem.c
  src/engine.cpp)

target_include_directories(ckdemo PUBLIC include PRIVATE src)

add_executable(ckdemo_cli src/main.c)
target_link_libraries(ckdemo_cli PRIVATE ckdemo)
