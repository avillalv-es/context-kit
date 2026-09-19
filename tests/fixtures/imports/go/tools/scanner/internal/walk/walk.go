package walk

// A grouped import written on ONE line. The specifiers are separated by
// semicolons, which is what the lexer inserts at the newlines of the usual
// multi-line form, so this is the same declaration written flat. It is legal
// Go and gofmt will not produce it.
//
// Note for the matcher: taking the FIRST quoted string on the line finds
// "os" and never sees "path/filepath". Both are standard library here, so
// nothing in this fixture's assertions depends on the second one - but on a
// line whose second specifier were an internal package, that import would be
// silently lost.
import ("os"; "path/filepath")

// Dirs lists one directory.
func Dirs(p string) ([]os.DirEntry, error) { return os.ReadDir(filepath.Clean(p)) }
