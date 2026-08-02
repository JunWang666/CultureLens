package contentadmin

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/goudaijun/culturelens-backend/internal/recognitionaudit"
	"github.com/jackc/pgx/v5"
)

func (r *PostgresRepository) RecentRecognitionRequests(
	ctx context.Context,
	limit int,
) ([]recognitionaudit.Summary, error) {
	if limit < 1 || limit > 100 {
		limit = 100
	}
	rows, err := r.pool.Query(ctx, `
SELECT
    id,
    request_id,
    received_at,
    completed_at,
    duration_ms,
    http_status,
    COALESCE(error_code, ''),
    request_body_bytes,
    request_payload,
    COALESCE(context_mime_type, ''),
    context_image_bytes,
    COALESCE(focus_mime_type, ''),
    focus_image_bytes,
    response_payload,
    COALESCE(model_identifier, ''),
    COALESCE(prompt_version, ''),
    COALESCE(schema_version, ''),
    COALESCE(resolution_status, ''),
    COALESCE(cultural_element_key, ''),
    COALESCE(canonical_name, '')
FROM recognition_request_logs
ORDER BY received_at DESC, id DESC
LIMIT $1`, limit)
	if err != nil {
		return nil, fmt.Errorf("query recent recognition requests: %w", err)
	}
	defer rows.Close()
	items := make([]recognitionaudit.Summary, 0, limit)
	for rows.Next() {
		var item recognitionaudit.Summary
		if err := rows.Scan(
			&item.ID,
			&item.RequestID,
			&item.ReceivedAt,
			&item.CompletedAt,
			&item.DurationMilliseconds,
			&item.HTTPStatus,
			&item.ErrorCode,
			&item.RequestBodyBytes,
			&item.RequestPayload,
			&item.ContextMIMEType,
			&item.ContextImageBytes,
			&item.FocusMIMEType,
			&item.FocusImageBytes,
			&item.ResponsePayload,
			&item.ModelIdentifier,
			&item.PromptVersion,
			&item.SchemaVersion,
			&item.ResolutionStatus,
			&item.CulturalElementKey,
			&item.CanonicalName,
		); err != nil {
			return nil, fmt.Errorf("scan recent recognition request: %w", err)
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate recent recognition requests: %w", err)
	}
	return items, nil
}

func (r *PostgresRepository) RecognitionRequestImage(
	ctx context.Context,
	id int64,
	kind string,
) (recognitionaudit.Image, error) {
	var query string
	switch strings.TrimSpace(kind) {
	case "context":
		query = `SELECT context_mime_type, context_image FROM recognition_request_logs WHERE id = $1 AND context_image IS NOT NULL`
	case "focus":
		query = `SELECT focus_mime_type, focus_image FROM recognition_request_logs WHERE id = $1 AND focus_image IS NOT NULL`
	default:
		return recognitionaudit.Image{}, recognitionaudit.ErrImageNotFound
	}
	var image recognitionaudit.Image
	if err := r.pool.QueryRow(ctx, query, id).Scan(&image.MIMEType, &image.Data); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return recognitionaudit.Image{}, recognitionaudit.ErrImageNotFound
		}
		return recognitionaudit.Image{}, fmt.Errorf("query recognition request image: %w", err)
	}
	return image, nil
}
