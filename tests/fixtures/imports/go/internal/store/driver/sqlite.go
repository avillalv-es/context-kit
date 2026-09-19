// Package driver registers the sqlite backend for the store.
package driver

import (
	"database/sql"

	"example.com/appsvc/internal/store"

	_ "github.com/mattn/go-sqlite3"
)

// Open dials the sqlite file backing the store.
func Open(dsn string) (*sql.DB, error) {
	return sql.Open("sqlite3", dsn)
}

// Seed writes one reading so a fresh database is never empty.
func Seed(db *sql.DB, r store.Reading) error {
	_, err := db.Exec("INSERT INTO readings (id, label) VALUES (?, ?)", r.ID, r.Label)
	return err
}
