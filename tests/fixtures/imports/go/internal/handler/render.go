package handler

import (
	"html/template"

	tel "example.com/appsvc/pkg/telemetry"
)

// usageText is a raw string literal on ONE line. It contains the word import
// and a quoted module path that resolves to a real directory in this
// fixture; render.go does not import config, so an extractor that reads
// quoted strings off any line will invent an edge here.
const usageText = `appsvc render -- not the same as import "example.com/appsvc/internal/config"`

// helpText is a raw string literal spanning MULTIPLE LINES. Go raw strings
// are delimited by backticks, not by quotes, and they run to the next
// backtick however many lines away that is - the one string form a
// quote-state scanner written for C-like languages does not see at all.
//
// The body below is laid out to look exactly like a grouped import
// declaration. A matcher that does not treat the backtick as a string
// delimiter opens grouped-import state on the "import (" line inside this
// literal and reads the following line as a module path. internal/util is a
// real directory, so the result is a clean, resolvable, fictional edge.
const helpText = `
usage: appsvc render [flags]

Before the handler split, rendering reached into the helpers directly:

import (
	"example.com/appsvc/internal/util"
)

It does not any more. Labels arrive already slugged.
`

var page = template.Must(template.New("row").Parse(`<li>{{.Label}}</li>`))

// Rows renders labels and counts the render.
func Rows(rows []string) string {
	c := tel.NewCounter("render rows")
	for range rows {
		c.Inc()
	}
	return usageText + helpText
}
