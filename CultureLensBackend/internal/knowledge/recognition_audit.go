package knowledge

import (
	"context"
	"fmt"

	"github.com/goudaijun/culturelens-backend/internal/recognitionaudit"
)

func (r *PostgresRepository) SaveRecognitionRequest(
	ctx context.Context,
	record recognitionaudit.Record,
) error {
	_, err := r.pool.Exec(ctx, `
INSERT INTO recognition_request_logs (
    request_id,
    received_at,
    completed_at,
    duration_ms,
    http_status,
    error_code,
    request_body_bytes,
    request_payload,
    context_image,
    context_mime_type,
    context_image_bytes,
    focus_image,
    focus_mime_type,
    focus_image_bytes,
    response_payload,
    model_identifier,
    prompt_version,
    schema_version,
    resolution_status,
    cultural_element_key,
    canonical_name
) VALUES (
    $1, $2, $3, $4, $5, NULLIF($6, ''), $7, $8,
    $9, NULLIF($10, ''), $11, $12, NULLIF($13, ''), $14, $15,
    NULLIF($16, ''), NULLIF($17, ''), NULLIF($18, ''), NULLIF($19, ''),
    NULLIF($20, ''), NULLIF($21, '')
)`,
		record.RequestID,
		record.ReceivedAt,
		record.CompletedAt,
		record.DurationMilliseconds,
		record.HTTPStatus,
		record.ErrorCode,
		record.RequestBodyBytes,
		nullableJSON(record.RequestPayload),
		nullableBytes(record.ContextImage),
		record.ContextMIMEType,
		len(record.ContextImage),
		nullableBytes(record.FocusImage),
		record.FocusMIMEType,
		len(record.FocusImage),
		record.ResponsePayload,
		record.ModelIdentifier,
		record.PromptVersion,
		record.SchemaVersion,
		record.ResolutionStatus,
		record.CulturalElementKey,
		record.CanonicalName,
	)
	if err != nil {
		return fmt.Errorf("insert recognition request audit: %w", err)
	}
	return nil
}

func nullableBytes(value []byte) any {
	if len(value) == 0 {
		return nil
	}
	return value
}

func nullableJSON(value []byte) any {
	if len(value) == 0 {
		return nil
	}
	return value
}
