// Command scanner is a SECOND MODULE inside the same repository: it has its
// own go.mod, and its module path (example.com/scanner) is unrelated to the
// root module path (example.com/appsvc).
//
// Resolution has to pick the module by the IMPORTING file's location, not by
// the repo root. Both imports below are in one block and each resolves
// against a different go.mod:
//
//   - example.com/scanner/... is this module, rooted at tools/scanner/
//   - example.com/appsvc/... is the root module, reached through the replace
//     directive above, and rooted at the repo root
//
// A resolver that reads only the root go.mod turns the first import into a
// third-party package and loses a real in-repo dependency.
package main

import (
	"fmt"

	"example.com/scanner/internal/walk"

	"example.com/appsvc/pkg/telemetry"
)

func main() {
	span := telemetry.Begin("scan")
	defer span.End()

	entries, err := walk.Dirs(".")
	if err != nil {
		return
	}
	fmt.Println(len(entries))
}
