// Package telemetry records timings for the service.
package telemetry

import (
	"log"
	"time"
)

// Span is one timed operation.
type Span struct {
	Name  string
	Start time.Time
}

// Begin opens a span.
func Begin(name string) *Span {
	return &Span{Name: name, Start: time.Now()}
}

// End closes a span and logs it.
func (s *Span) End() {
	log.Printf("span %s took %s", s.Name, time.Since(s.Start))
}
