package database_test

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/goudaijun/culturelens-backend/internal/database"
	"github.com/goudaijun/culturelens-backend/internal/database/dbgen"
	"github.com/jackc/pgx/v5"
)

var testIntroduction = []byte(`{
  "schemaVersion": 1,
  "blocks": [{"type": "paragraph", "text": "测试介绍"}]
}`)

func TestCulturalContentSchemaAndQueries(t *testing.T) {
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

	queries := dbgen.New(connection)
	for _, input := range []dbgen.UpsertCulturalElementParams{
		{
			ElementKey:   "timber-bracket",
			Name:         "斗拱",
			Introduction: testIntroduction,
		},
		{
			ElementKey:   "mortise-and-tenon",
			Name:         "榫卯",
			Introduction: testIntroduction,
		},
	} {
		if _, err := queries.UpsertCulturalElement(ctx, input); err != nil {
			t.Fatal(err)
		}
	}
	if err := queries.InsertCulturalElementRelation(
		ctx,
		dbgen.InsertCulturalElementRelationParams{
			ElementKey:        "timber-bracket",
			RelatedElementKey: "mortise-and-tenon",
		},
	); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"timber-bracket", "mortise-and-tenon"} {
		related, err := queries.ListRelatedCulturalElements(
			ctx,
			dbgen.ListRelatedCulturalElementsParams{
				ElementKey:   key,
				RelatedLimit: 12,
			},
		)
		if err != nil {
			t.Fatal(err)
		}
		if len(related) != 1 {
			t.Fatalf("related elements for %s = %+v", key, related)
		}
	}
	if err := queries.InsertCulturalElementRelation(
		ctx,
		dbgen.InsertCulturalElementRelationParams{
			ElementKey:        "mortise-and-tenon",
			RelatedElementKey: "timber-bracket",
		},
	); err == nil {
		t.Fatal("expected reverse duplicate relation to be rejected")
	}

	if _, err := queries.UpsertAttraction(
		ctx,
		dbgen.UpsertAttractionParams{
			AttractionKey: "hangzhou-west-lake",
			Name:          "杭州西湖文化景观",
		},
	); err != nil {
		t.Fatal(err)
	}
	created, err := queries.UpsertAttractionCulturalIntroduction(
		ctx,
		dbgen.UpsertAttractionCulturalIntroductionParams{
			IntroductionKey:    "west-lake.test.timber-bracket",
			Name:               "西湖现场的斗拱",
			Introduction:       testIntroduction,
			CulturalElementKey: "timber-bracket",
			AttractionKey:      "hangzhou-west-lake",
			Latitude:           30.248963,
			Longitude:          120.148691,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if created.CulturalElementKey != "timber-bracket" ||
		created.AttractionKey != "hangzhou-west-lake" ||
		created.Latitude != 30.248963 ||
		created.Longitude != 120.148691 {
		t.Fatalf("unexpected introduction: %+v", created)
	}
	loaded, err := queries.GetAttractionCulturalIntroduction(
		ctx,
		"west-lake.test.timber-bracket",
	)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.CulturalElementName != "斗拱" ||
		loaded.AttractionName != "杭州西湖文化景观" {
		t.Fatalf("unexpected hydrated introduction: %+v", loaded)
	}

	assertRejected(t, ctx, connection,
		`INSERT INTO cultural_elements (key, name, introduction)
		 VALUES ('INVALID KEY', '无效', $1)`,
		testIntroduction,
	)
	assertRejected(t, ctx, connection,
		`INSERT INTO cultural_elements (key, name, introduction)
		 VALUES ('empty-rich-text', '无效', '{"schemaVersion":1,"blocks":[]}'::jsonb)`,
	)
	assertRejected(t, ctx, connection,
		`INSERT INTO attraction_cultural_introductions (
		   key, name, introduction, cultural_element_key, attraction_key,
		   latitude, longitude
		 ) VALUES (
		   'invalid-coordinate', '无效坐标', $1,
		   'timber-bracket', 'hangzhou-west-lake', 91, 120
		 )`,
		testIntroduction,
	)
	assertRejected(t, ctx, connection,
		`INSERT INTO cultural_element_relations (element_key, related_element_key)
		 VALUES ('timber-bracket', 'timber-bracket')`,
	)
}

func assertRejected(
	t *testing.T,
	ctx context.Context,
	connection *pgx.Conn,
	statement string,
	arguments ...any,
) {
	t.Helper()
	if _, err := connection.Exec(ctx, statement, arguments...); err == nil {
		t.Fatalf("expected PostgreSQL to reject statement: %s", statement)
	}
}
