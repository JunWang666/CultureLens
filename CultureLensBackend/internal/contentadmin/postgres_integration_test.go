package contentadmin

import (
	"context"
	"encoding/json"
	"os"
	"testing"
	"time"

	"github.com/goudaijun/culturelens-backend/internal/database"
	"github.com/goudaijun/culturelens-backend/internal/knowledge"
	"github.com/jackc/pgx/v5"
)

func TestPostgresAdminImportAndNearbyQuery(t *testing.T) {
	databaseURL := os.Getenv("TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("TEST_DATABASE_URL is not configured")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	connection, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	version, err := database.Migrate(ctx, connection)
	if err != nil {
		t.Fatal(err)
	}
	if version != 7 {
		t.Fatalf("schema version = %d, expected 7", version)
	}
	if _, err := connection.Exec(
		ctx,
		`TRUNCATE cultural_elements, attractions CASCADE`,
	); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile("../../content/hangzhou-west-lake.v1.json")
	if err != nil {
		t.Fatal(err)
	}
	var bundle Bundle
	if err := json.Unmarshal(data, &bundle); err != nil {
		t.Fatal(err)
	}
	if err := ValidateBundle(bundle); err != nil {
		t.Fatal(err)
	}
	repository, err := NewPostgresRepository(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer repository.Close()
	for attempt := 0; attempt < 2; attempt++ {
		result, err := repository.Import(ctx, bundle)
		if err != nil {
			t.Fatal(err)
		}
		if result.Elements != 34 || result.Relations != 44 || result.Introductions != 19 {
			t.Fatalf("unexpected import result: %+v", result)
		}
	}
	snapshot, err := repository.Snapshot(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(snapshot.Elements) != 34 ||
		len(snapshot.Attractions) != 7 ||
		len(snapshot.Relations) != 44 ||
		len(snapshot.Introductions) != 19 {
		t.Fatalf("unexpected snapshot counts: %+v", snapshot)
	}
	introduction := snapshot.Introductions[0]
	introduction.Latitude = 30.25
	introduction.Longitude = 120.15
	saved, err := repository.UpsertIntroduction(ctx, introduction)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Latitude != 30.25 || saved.Longitude != 120.15 {
		t.Fatalf("coordinate update was not saved: %+v", saved)
	}

	publicRepository, err := knowledge.NewPostgresRepository(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer publicRepository.Close()
	nearby, err := publicRepository.NearbyIntroductions(
		ctx,
		knowledge.NearbyIntroductionQuery{
			Latitude:     30.233889,
			Longitude:    120.145,
			RadiusMeters: 50,
			Limit:        12,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if nearby.TotalMatches != 2 || len(nearby.Introductions) != 2 {
		t.Fatalf("unexpected Leifeng recommendations: %+v", nearby)
	}
}
