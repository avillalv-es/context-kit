package main

import (
	"testing"

	. "example.com/appsvc/internal/util"
)

// TestSlugDot uses a DOT import: the exported names of internal/util land in
// this file's scope, so Slug is called unqualified. The leading "." must not
// block the capture, exactly like the "_" of a blank import and the "tel" of
// an aliased one. Anchoring the capture at ^[ \t]*" misses all three.
func TestSlugDot(t *testing.T) {
	if Slug("Vault Room 3") != "vault-room-3" {
		t.Fatalf("slug")
	}
}
