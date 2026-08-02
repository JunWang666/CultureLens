DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'culturelens_editor'
    ) THEN
        GRANT USAGE ON SCHEMA public TO culturelens_editor;
        GRANT SELECT, INSERT, UPDATE ON
            cultural_elements,
            cultural_element_relations,
            attractions,
            attraction_cultural_introductions
        TO culturelens_editor;
    END IF;
END
$$;

---- create above / drop below ----

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'culturelens_editor'
    ) THEN
        REVOKE SELECT, INSERT, UPDATE ON
            cultural_elements,
            cultural_element_relations,
            attractions,
            attraction_cultural_introductions
        FROM culturelens_editor;
        REVOKE USAGE ON SCHEMA public FROM culturelens_editor;
    END IF;
END
$$;
