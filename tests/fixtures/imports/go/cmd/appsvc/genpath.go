package main

// Emitted by a codegen pass that joined the module path with a relative
// fragment and got the join wrong. Neither specifier can name a file:
//
//   - the bare module path leaves an EMPTY remainder once the prefix is
//     stripped. Treated as a directory, "" is the repo root, which would fan
//     out to every .go file in the fixture.
//   - the second climbs with ../.. past the module root. It must be rejected
//     outright, not clamped to the root, because a clamped path silently
//     resolves to the wrong file.
//
// Go itself rejects "." and ".." elements in an import path, so this file is
// deliberately not buildable. It exists to feed the resolver the two path
// shapes that have no file behind them.
import (
	"example.com/appsvc"
	"example.com/appsvc/internal/../../../outside/thing"
)
