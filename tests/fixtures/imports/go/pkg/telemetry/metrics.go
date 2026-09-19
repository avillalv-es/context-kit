package telemetry

import "example.com/appsvc/internal/util"

// Counter is a named tally.
type Counter struct {
	key string
	n   int
}

// NewCounter normalises the name through util so metric keys stay stable.
func NewCounter(name string) *Counter {
	return &Counter{key: util.Slug(name)}
}

// Inc adds one.
func (c *Counter) Inc() { c.n++ }
