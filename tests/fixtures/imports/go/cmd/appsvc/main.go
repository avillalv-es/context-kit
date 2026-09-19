// Command appsvc is the fixture entry point.
//
// Historical note: this file once reached straight into the helpers with
//
//	import "example.com/appsvc/internal/util"
//
// before handler was split out. That line is a comment now, and internal/util
// is a real directory, so it is the sharpest false edge in this fixture.
package main

import (
	"context"
	"log"
	"os"

	"example.com/appsvc/internal/config"
	"example.com/appsvc/internal/handler"
	// "example.com/appsvc/pkg/telemetry" // reached through handler now, see ADR-014
	_ "example.com/appsvc/internal/store/driver"

	"github.com/google/uuid"
)

func main() {
	ctx := context.Background()
	cfg := config.Load()

	log.Printf("run %s starting %s on :%d", uuid.NewString(), cfg.Name, cfg.Port)

	api := &handler.API{}
	if err := run(ctx, api); err != nil {
		log.Println(err)
		os.Exit(1)
	}
}

func run(ctx context.Context, api *handler.API) error {
	<-ctx.Done()
	_ = api
	return ctx.Err()
}
