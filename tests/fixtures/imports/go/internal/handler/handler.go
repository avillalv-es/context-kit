// Package handler serves the HTTP surface.
package handler

import (
	"encoding/json"
	"net/http"

	"example.com/appsvc/internal/store"
	"example.com/appsvc/pkg/telemetry"
	/* "example.com/appsvc/internal/store/driver" */

	// Two sibling third-party modules whose paths string-prefix this module's
	// own path (example.com/appsvc) without being inside it. The prefix test
	// has to end on a path boundary - "/" or end-of-string - not merely match
	// as a string.
	//
	// The two differ in how loudly they fail. Strip 18 characters off the
	// first and the remainder is "-contrib/ratelimit", which matches no
	// directory, so a missing boundary check is hidden: the import drops by
	// luck. Strip 18 off the second and the remainder is "internal/util",
	// which is a real directory here, so the same missing check produces a
	// resolvable edge to internal/util/strings.go. handler.go imports nothing
	// from internal/util, so that edge shows up in the diff instead of being
	// deduplicated against a true one.
	"example.com/appsvc-contrib/ratelimit"
	xutil "example.com/appsvcinternal/util"
)

// API wires the store to HTTP.
type API struct {
	Store *store.Memory
	Limit ratelimit.Limiter
}

// ServeHTTP writes one reading as JSON.
func (a *API) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	span := telemetry.Begin("serve")
	defer span.End()

	id := r.URL.Query().Get("id")
	if !xutil.NonEmpty(id) {
		http.Error(w, "missing id", http.StatusBadRequest)
		return
	}

	row, err := a.Store.Get(id)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}
	_ = json.NewEncoder(w).Encode(row)
}
