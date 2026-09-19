// Package uuid is a VENDORED copy of the third-party module, checked in
// under vendor/ the way `go mod vendor` writes it.
//
// This file makes the repo contain a real .go file at the exact path the
// import "github.com/google/uuid" spells. cmd/appsvc/main.go and
// internal/store/store.go both import it, and both must still drop it: an
// external module is not an in-repo dependency, and the resolver keys on the
// module path from go.mod, not on any directory that happens to match.
//
// A suffix or basename fallback links every one of those imports here.
package uuid

func NewString() string { return "00000000-0000-0000-0000-000000000000" }
