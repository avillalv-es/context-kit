package main

import (
	"testing"

	"example.com/appsvc/internal/config"
	"example.com/appsvc/internal/store"
)

func TestLoadAndPut(t *testing.T) {
	cfg := config.Load()
	m := store.NewMemory(cfg)

	r := store.NewReading("Vault Room 3", 0.42)
	m.Put(r)

	got, err := m.Get(r.ID)
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Label != "vault-room-3" {
		t.Fatalf("label = %q", got.Label)
	}
}
