CREATE TABLE knowledge_edges (
    id UUID PRIMARY KEY,
    catalog_version TEXT NOT NULL
        REFERENCES knowledge_catalogs(version)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    source_id UUID NOT NULL
        REFERENCES knowledge_nodes(id)
        ON DELETE CASCADE,
    target_id UUID NOT NULL
        REFERENCES knowledge_nodes(id)
        ON DELETE CASCADE,
    relation_kind TEXT NOT NULL CHECK (btrim(relation_kind) <> ''),
    explanation TEXT NOT NULL CHECK (btrim(explanation) <> ''),
    status TEXT NOT NULL CHECK (status IN ('imported', 'reviewed', 'archived')),
    content_version BIGINT NOT NULL DEFAULT 1 CHECK (content_version > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (source_id <> target_id),
    UNIQUE (catalog_version, source_id, target_id, relation_kind)
);

CREATE INDEX knowledge_edges_source_idx
    ON knowledge_edges (catalog_version, status, source_id);

CREATE INDEX knowledge_edges_target_idx
    ON knowledge_edges (catalog_version, status, target_id);

CREATE TABLE edge_sources (
    edge_id UUID NOT NULL
        REFERENCES knowledge_edges(id)
        ON DELETE CASCADE,
    source_id UUID NOT NULL
        REFERENCES knowledge_sources(id)
        ON DELETE RESTRICT,
    evidence_note TEXT NOT NULL DEFAULT '',
    sort_order INTEGER NOT NULL CHECK (sort_order >= 0),
    PRIMARY KEY (edge_id, source_id),
    UNIQUE (edge_id, sort_order)
);

CREATE INDEX edge_sources_source_idx ON edge_sources (source_id);

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'culturelens_app'
    ) THEN
        GRANT SELECT ON knowledge_edges, edge_sources TO culturelens_app;
    END IF;
END
$$;

---- create above / drop below ----

DROP TABLE edge_sources;
DROP TABLE knowledge_edges;
