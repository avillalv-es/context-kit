// Package handler serves the HTTP surface.
package handler

import (
	"encoding/json"
	"net/http"

	"example.com/appsvc/internal/store"
	"example.com/appsvc/pkg/telemetry"

	"example.com/appsvc-contrib/ratelimit"
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

	row, err := a.Store.Get(r.URL.Query().Get("id"))
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}
	_ = json.NewEncoder(w).Encode(row)
}
