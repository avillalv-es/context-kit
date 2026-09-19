package handler

import (
	"html/template"

	tel "example.com/appsvc/pkg/telemetry"
)

// usageText is a raw string literal. It contains the word import and a
// quoted module path that resolves to a real directory in this fixture;
// render.go does not import config, so an extractor that reads quoted
// strings off any line will invent an edge here.
const usageText = `appsvc render -- not the same as import "example.com/appsvc/internal/config"`

var page = template.Must(template.New("row").Parse(`<li>{{.Label}}</li>`))

// Rows renders labels and counts the render.
func Rows(rows []string) string {
	c := tel.NewCounter("render rows")
	for range rows {
		c.Inc()
	}
	return usageText
}
