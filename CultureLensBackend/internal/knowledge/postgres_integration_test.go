package knowledge

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/goudaijun/culturelens-backend/internal/database"
	"github.com/jackc/pgx/v5"
)

func TestPostgresContentRepositoryOnRetiredLegacySchema(t *testing.T) {
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
		t.Fatalf("schema version=%d, expected 7", version)
	}
	for _, table := range []string{
		"knowledge_catalogs", "knowledge_nodes", "knowledge_aliases",
		"knowledge_geographies", "knowledge_sources", "node_sources",
		"knowledge_edges", "edge_sources",
	} {
		var exists bool
		if err := connection.QueryRow(
			ctx,
			`SELECT to_regclass('public.' || $1) IS NOT NULL`,
			table,
		).Scan(&exists); err != nil {
			t.Fatal(err)
		}
		if exists {
			t.Fatalf("legacy table %s still exists", table)
		}
	}
	if _, err := connection.Exec(ctx, `TRUNCATE cultural_elements, attractions CASCADE`); err != nil {
		t.Fatal(err)
	}
	richText := []byte(`{"schemaVersion":1,"blocks":[{"type":"paragraph","text":"测试介绍"}]}`)
	statements := []struct {
		sql  string
		args []any
	}{
		{
			sql: `INSERT INTO cultural_elements (key, name, introduction) VALUES
			 ($1, '斗拱', $3), ($2, '榫卯', $3), ('lake-moon', '湖上月景', $3)`,
			args: []any{"timber-bracket", "mortise-and-tenon", richText},
		},
		{
			sql:  `INSERT INTO cultural_element_relations (element_key, related_element_key) VALUES ($1, $2)`,
			args: []any{"timber-bracket", "mortise-and-tenon"},
		},
		{sql: `INSERT INTO attractions (key, name) VALUES ('timber-bracket', '杭州西湖文化景观')`},
		{
			sql: `INSERT INTO attraction_cultural_introductions (
			 key, name, introduction, cultural_element_key, attraction_key, latitude, longitude
			) VALUES
			 ('west-lake.exact', '精确点', $1, 'mortise-and-tenon', 'timber-bracket', 30.248963, 120.148691),
			 ('west-lake.north', '北侧点', $1, 'timber-bracket', 'timber-bracket', 30.249963, 120.148691),
			 ('west-lake.moon', '月景点', $1, 'lake-moon', 'timber-bracket', 30.249963, 120.148691)`,
			args: []any{richText},
		},
	}
	for _, statement := range statements {
		if _, err := connection.Exec(ctx, statement.sql, statement.args...); err != nil {
			t.Fatal(err)
		}
	}
	repository, err := NewPostgresRepository(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer repository.Close()
	stats := repository.Stats()
	if stats.CulturalElementCount != 3 || stats.IntroductionCount != 3 {
		t.Fatalf("unexpected content stats: %+v", stats)
	}
	related, err := repository.RelatedElements(ctx, "timber-bracket", 12)
	if err != nil || len(related.RelatedElements) != 1 || related.RelatedElements[0].Key != "mortise-and-tenon" {
		t.Fatalf("unexpected related set: set=%+v err=%v", related, err)
	}
	if _, err := repository.RelatedElements(ctx, "missing", 12); !errors.Is(err, ErrCulturalElementNotFound) {
		t.Fatalf("expected ErrCulturalElementNotFound, got %v", err)
	}
	recognition, err := repository.RecognitionKnowledge(ctx, RecognitionQuery{
		Latitude: 30.248963, Longitude: 120.148691, RadiusMeters: 200, HasLocation: true, Limit: 12,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(recognition.AttractionCandidates) != 1 ||
		recognition.AttractionCandidates[0].CulturalElementKey != "mortise-and-tenon" ||
		len(recognition.Elements) != 3 || recognition.Elements[0].Key != "mortise-and-tenon" ||
		len(recognition.Elements[0].GraphElements) != 2 ||
		len(recognition.Elements[0].GraphRelations) != 2 {
		t.Fatalf("attraction graph was not preserved: %+v", recognition)
	}
}
