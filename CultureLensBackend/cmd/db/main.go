package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/goudaijun/culturelens-backend/internal/database"
	"github.com/jackc/pgx/v5"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	command := "up"
	if len(os.Args) > 1 {
		command = os.Args[1]
	}
	if command != "up" && command != "migrate" {
		return fmt.Errorf(
			"unsupported command %q; use up or migrate",
			command,
		)
	}
	databaseURL := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if databaseURL == "" {
		return errors.New("DATABASE_URL is required")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	connection, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		return fmt.Errorf("connect PostgreSQL: %w", err)
	}
	defer connection.Close(context.Background())

	if command == "up" || command == "migrate" {
		version, err := database.Migrate(ctx, connection)
		if err != nil {
			return err
		}
		fmt.Printf("schema_version=%d\n", version)
	}
	return nil
}
