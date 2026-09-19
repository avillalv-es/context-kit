package telemetry

// This file is named config.go and there is another config.go in this
// fixture, at internal/config/config.go. A resolver that falls back to a
// basename or a unique-suffix match when a directory lookup misses has two
// candidates for "config" and no way to choose; a resolver that takes the
// FIRST match links the wrong pair. Both directories are imported by real
// code here, so the wrong choice is not visibly wrong in the output.
//
// A Go import names a directory, so this file is also one more member of the
// telemetry package: every importer of pkg/telemetry must reach it.

import (
	"example.com/appsvc/internal/config"
)

// Sink is where spans and counters are written.
type Sink struct {
	Addr string
	Name string
}

// SinkFor builds the sink for a loaded service configuration.
func SinkFor(cfg config.Config) Sink {
	return Sink{Addr: "127.0.0.1:9009", Name: cfg.Name}
}
