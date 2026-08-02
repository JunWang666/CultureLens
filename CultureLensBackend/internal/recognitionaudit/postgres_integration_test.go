package recognitionaudit_test

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/goudaijun/culturelens-backend/internal/contentadmin"
	"github.com/goudaijun/culturelens-backend/internal/database"
	"github.com/goudaijun/culturelens-backend/internal/knowledge"
	"github.com/goudaijun/culturelens-backend/internal/recognitionaudit"
	"github.com/jackc/pgx/v5"
)

func TestPostgresRecognitionAuditWriteListAndImage(t *testing.T) {
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
	if _, err := connection.Exec(ctx, `TRUNCATE recognition_request_logs RESTART IDENTITY`); err != nil {
		t.Fatal(err)
	}

	writer, err := knowledge.NewPostgresRepository(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer writer.Close()
	reader, err := contentadmin.NewPostgresRepository(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()

	baseTime := time.Now().UTC().Add(-time.Minute)
	for index := 0; index < 3; index++ {
		stamp := baseTime.Add(time.Duration(index) * time.Second)
		record := recognitionaudit.Record{
			RequestID:            "request-" + string(rune('a'+index)),
			ReceivedAt:           stamp,
			CompletedAt:          stamp.Add(25 * time.Millisecond),
			DurationMilliseconds: 25,
			HTTPStatus:           200,
			RequestBodyBytes:     123,
			RequestPayload:       json.RawMessage(`{"locale":"zh_CN"}`),
			ContextImage:         []byte{byte(index), 2, 3},
			ContextMIMEType:      "image/jpeg",
			ResponsePayload:      json.RawMessage(`{"status":"ok"}`),
			ModelIdentifier:      "gemini-test",
			PromptVersion:        "recognition-v5",
			CanonicalName:        "测试对象",
		}
		if err := writer.SaveRecognitionRequest(ctx, record); err != nil {
			t.Fatal(err)
		}
	}
	if err := writer.SaveRecognitionRequest(ctx, recognitionaudit.Record{
		RequestID:            "request-d",
		ReceivedAt:           baseTime.Add(3 * time.Second),
		CompletedAt:          baseTime.Add(3*time.Second + 5*time.Millisecond),
		DurationMilliseconds: 5,
		HTTPStatus:           400,
		ErrorCode:            "invalid_request",
		RequestBodyBytes:     9,
		ResponsePayload:      json.RawMessage(`{"error":{"code":"invalid_request"}}`),
	}); err != nil {
		t.Fatal(err)
	}

	items, err := reader.RecentRecognitionRequests(ctx, 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 2 ||
		items[0].RequestID != "request-d" ||
		items[0].ErrorCode != "invalid_request" ||
		len(items[0].RequestPayload) != 0 ||
		items[1].RequestID != "request-c" ||
		items[1].ContextImageBytes != 3 {
		t.Fatalf("unexpected recent audits: %+v", items)
	}
	image, err := reader.RecognitionRequestImage(ctx, items[1].ID, "context")
	if err != nil {
		t.Fatal(err)
	}
	if image.MIMEType != "image/jpeg" || len(image.Data) != 3 || image.Data[0] != 2 {
		t.Fatalf("unexpected image: %+v", image)
	}
	if _, err := reader.RecognitionRequestImage(ctx, items[1].ID, "focus"); !errors.Is(err, recognitionaudit.ErrImageNotFound) {
		t.Fatalf("expected ErrImageNotFound, got %v", err)
	}
}
