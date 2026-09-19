// Package util holds leaf-level helpers. It imports nothing inside this
// module, which is what keeps the fixture free of cycles.
package util

import "strings"

/*
Historical wiring, kept only as a note. Before the handler split this file
reached upward and did:

	import (
		"example.com/appsvc/internal/store"
		"example.com/appsvc/pkg/telemetry"
	)

Both paths resolve to real directories in this fixture, so an extractor that
does not strip block comments will invent two edges that do not exist.
*/

// Slug lowercases and hyphenates a label.
func Slug(s string) string {
	return strings.ReplaceAll(strings.ToLower(strings.TrimSpace(s)), " ", "-")
}
