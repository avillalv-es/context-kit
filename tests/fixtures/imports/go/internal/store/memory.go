package store

import (
	"sync"

	"example.com/appsvc/internal/config"
)

// Ported from the old GOPATH tree, where this file began with
//	import "./config"
// Relative import paths are not legal in module mode, and a commented-out
// import is not a dependency either. Neither line may become an edge.

// Memory is an in-process Store.
type Memory struct {
	mu   sync.Mutex
	cap  int
	rows map[string]Reading
}

// NewMemory sizes the store from configuration.
func NewMemory(cfg config.Config) *Memory {
	return &Memory{cap: cfg.Port, rows: make(map[string]Reading)}
}

// Put stores a reading.
func (m *Memory) Put(r Reading) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.rows[r.ID] = r
}

// Get returns a reading or ErrNotFound.
func (m *Memory) Get(id string) (Reading, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, ok := m.rows[id]
	if !ok {
		return Reading{}, ErrNotFound
	}
	return r, nil
}
