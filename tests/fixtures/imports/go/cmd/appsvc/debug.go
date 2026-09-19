package main

// The import block below is EMPTY: a refactor tool removed the last
// specifier and left the parentheses behind. `import ()` is legal Go, and it
// opens and closes on the same line.
//
// A matcher that opens grouped-import state on a line matching `import (`
// and only closes it on a line that STARTS with `)` never closes here, so
// every quoted string in the rest of the file is read as a module path. The
// constant below names a real package directory, so the leak produces a
// fully resolvable edge that does not exist. debug.go imports nothing.
import ()

// DocPath is printed by `appsvc --debug` so support can see which package
// owns configuration. It is documentation, not a dependency.
const DocPath = "example.com/appsvc/internal/config"
