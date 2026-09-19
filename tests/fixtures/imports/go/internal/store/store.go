// Package store defines the reading store and its errors.
package store

import (
	"errors"

	"example.com/appsvc/internal/util"

	"github.com/google/uuid"
)

// ErrNotFound is returned when a reading is absent.
var ErrNotFound = errors.New("store: not found")

// Reading is one recorded sample.
type Reading struct {
	ID    string
	Label string
	Value float64
}

// NewReading mints a reading with a normalised label.
func NewReading(label string, value float64) Reading {
	return Reading{ID: uuid.NewString(), Label: util.Slug(label), Value: value}
}
