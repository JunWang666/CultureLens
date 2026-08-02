package database

import (
	"context"
	"embed"
	"fmt"
	"io/fs"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/tern/v2/migrate"
)

const schemaVersionTable = "public.culturelens_schema_version"

//go:embed migrations/*.sql
var migrationFiles embed.FS

func Migrate(ctx context.Context, connection *pgx.Conn) (int32, error) {
	files, err := fs.Sub(migrationFiles, "migrations")
	if err != nil {
		return 0, fmt.Errorf("open embedded migrations: %w", err)
	}
	migrator, err := migrate.NewMigrator(ctx, connection, schemaVersionTable)
	if err != nil {
		return 0, fmt.Errorf("initialize migrator: %w", err)
	}
	if err := migrator.LoadMigrations(files); err != nil {
		return 0, fmt.Errorf("load migrations: %w", err)
	}
	if err := migrator.Migrate(ctx); err != nil {
		return 0, fmt.Errorf("apply migrations: %w", err)
	}
	version, err := migrator.GetCurrentVersion(ctx)
	if err != nil {
		return 0, fmt.Errorf("read schema version: %w", err)
	}
	return version, nil
}
