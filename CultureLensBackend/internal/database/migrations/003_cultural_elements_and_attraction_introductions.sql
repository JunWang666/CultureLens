CREATE TABLE cultural_elements (
    key TEXT PRIMARY KEY CHECK (
        key ~ '^[a-z0-9][a-z0-9._-]{0,127}$'
    ),
    name TEXT NOT NULL CHECK (btrim(name) <> ''),
    introduction JSONB NOT NULL CHECK (
        jsonb_typeof(introduction) = 'object'
        AND introduction ? 'schemaVersion'
        AND introduction ->> 'schemaVersion' = '1'
        AND introduction ? 'blocks'
        AND jsonb_typeof(introduction -> 'blocks') = 'array'
        AND jsonb_array_length(introduction -> 'blocks') > 0
    ),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE cultural_element_relations (
    element_key TEXT NOT NULL
        REFERENCES cultural_elements(key)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    related_element_key TEXT NOT NULL
        REFERENCES cultural_elements(key)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (element_key, related_element_key),
    CHECK (element_key <> related_element_key)
);

CREATE UNIQUE INDEX cultural_element_relations_undirected_idx
    ON cultural_element_relations (
        LEAST(element_key, related_element_key),
        GREATEST(element_key, related_element_key)
    );

CREATE INDEX cultural_element_relations_related_idx
    ON cultural_element_relations (related_element_key, element_key);

CREATE TABLE attractions (
    key TEXT PRIMARY KEY CHECK (
        key ~ '^[a-z0-9][a-z0-9._-]{0,127}$'
    ),
    name TEXT NOT NULL CHECK (btrim(name) <> ''),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE attraction_cultural_introductions (
    key TEXT PRIMARY KEY CHECK (
        key ~ '^[a-z0-9][a-z0-9._-]{0,127}$'
    ),
    name TEXT NOT NULL CHECK (btrim(name) <> ''),
    introduction JSONB NOT NULL CHECK (
        jsonb_typeof(introduction) = 'object'
        AND introduction ? 'schemaVersion'
        AND introduction ->> 'schemaVersion' = '1'
        AND introduction ? 'blocks'
        AND jsonb_typeof(introduction -> 'blocks') = 'array'
        AND jsonb_array_length(introduction -> 'blocks') > 0
    ),
    cultural_element_key TEXT NOT NULL
        REFERENCES cultural_elements(key)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    attraction_key TEXT NOT NULL
        REFERENCES attractions(key)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX attraction_cultural_introductions_attraction_idx
    ON attraction_cultural_introductions (attraction_key, name, key);

CREATE INDEX attraction_cultural_introductions_element_idx
    ON attraction_cultural_introductions (cultural_element_key, attraction_key);

CREATE INDEX attraction_cultural_introductions_coordinate_idx
    ON attraction_cultural_introductions (latitude, longitude);

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'culturelens_app'
    ) THEN
        GRANT SELECT ON
            cultural_elements,
            cultural_element_relations,
            attractions,
            attraction_cultural_introductions
        TO culturelens_app;
    END IF;
END
$$;

---- create above / drop below ----

DROP TABLE attraction_cultural_introductions;
DROP TABLE attractions;
DROP TABLE cultural_element_relations;
DROP TABLE cultural_elements;
