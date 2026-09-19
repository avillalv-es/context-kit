package telemetry

// One line carrying three things a matcher has to get right at once: the
// single-line import form with no parentheses, a /* */ comment that opens
// and closes mid-line and must not swallow the specifier after it, and a //
// comment holding a second, different module path that must not be read.
import /* leaf helper */ "example.com/appsvc/internal/util" // was "example.com/appsvc/internal/store"

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
