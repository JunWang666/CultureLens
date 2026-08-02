CREATE TABLE recognition_request_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_id TEXT NOT NULL CHECK (btrim(request_id) <> ''),
    received_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ NOT NULL,
    duration_ms BIGINT NOT NULL CHECK (duration_ms >= 0),
    http_status SMALLINT NOT NULL CHECK (http_status BETWEEN 100 AND 599),
    error_code TEXT,
    request_body_bytes BIGINT NOT NULL CHECK (request_body_bytes >= 0),
    request_payload JSONB,
    context_image BYTEA,
    context_mime_type TEXT,
    context_image_bytes BIGINT NOT NULL DEFAULT 0 CHECK (context_image_bytes >= 0),
    focus_image BYTEA,
    focus_mime_type TEXT,
    focus_image_bytes BIGINT NOT NULL DEFAULT 0 CHECK (focus_image_bytes >= 0),
    response_payload JSONB NOT NULL,
    model_identifier TEXT,
    prompt_version TEXT,
    schema_version TEXT,
    resolution_status TEXT,
    cultural_element_key TEXT,
    canonical_name TEXT,
    CHECK ((context_image IS NULL) = (context_mime_type IS NULL)),
    CHECK ((focus_image IS NULL) = (focus_mime_type IS NULL)),
    CHECK (context_image_bytes = octet_length(COALESCE(context_image, ''::bytea))),
    CHECK (focus_image_bytes = octet_length(COALESCE(focus_image, ''::bytea)))
);

CREATE INDEX recognition_request_logs_recent_idx
    ON recognition_request_logs (received_at DESC, id DESC);

CREATE INDEX recognition_request_logs_request_id_idx
    ON recognition_request_logs (request_id);

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'culturelens_app'
    ) THEN
		REVOKE ALL PRIVILEGES ON recognition_request_logs FROM culturelens_app;
		REVOKE ALL PRIVILEGES ON SEQUENCE recognition_request_logs_id_seq FROM culturelens_app;
        GRANT INSERT ON recognition_request_logs TO culturelens_app;
		GRANT USAGE ON SEQUENCE recognition_request_logs_id_seq TO culturelens_app;
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'culturelens_editor'
    ) THEN
		REVOKE ALL PRIVILEGES ON recognition_request_logs FROM culturelens_editor;
        GRANT SELECT ON recognition_request_logs TO culturelens_editor;
    END IF;
END
$$;

---- create above / drop below ----

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'culturelens_editor'
    ) THEN
        REVOKE SELECT ON recognition_request_logs FROM culturelens_editor;
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'culturelens_app'
    ) THEN
		REVOKE USAGE ON SEQUENCE recognition_request_logs_id_seq FROM culturelens_app;
        REVOKE INSERT ON recognition_request_logs FROM culturelens_app;
    END IF;
END
$$;

DROP TABLE recognition_request_logs;
