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

-- This corrective migration intentionally keeps the least-privilege grants when
-- rolling the schema version back. Restoring broader inherited privileges would
-- expose retained user photos to the runtime role.
SELECT 1;
