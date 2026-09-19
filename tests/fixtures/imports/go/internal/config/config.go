// Package config reads service settings from the environment.
package config

import (
	"os"
	"strconv"

	"example.com/appsvc/internal/util"
)

// Config is the resolved service configuration.
type Config struct {
	Name string
	Port int
}

// Load builds a Config from the environment.
func Load() Config {
	port, _ := strconv.Atoi(os.Getenv("APPSVC_PORT"))
	if port == 0 {
		port = 8080
	}
	return Config{Name: util.Slug(os.Getenv("APPSVC_NAME")), Port: port}
}
