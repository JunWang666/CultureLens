CREATE TABLE knowledge_catalogs (
    version TEXT PRIMARY KEY CHECK (btrim(version) <> ''),
    source_sha256 TEXT NOT NULL CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
    is_active BOOLEAN NOT NULL DEFAULT FALSE,
    object_count INTEGER NOT NULL CHECK (object_count >= 0),
    imported_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX knowledge_catalogs_one_active_idx
    ON knowledge_catalogs (is_active)
    WHERE is_active;

CREATE TABLE knowledge_nodes (
    id UUID PRIMARY KEY,
    catalog_version TEXT NOT NULL
        REFERENCES knowledge_catalogs(version)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    node_type TEXT NOT NULL CHECK (node_type IN ('object', 'concept')),
    canonical_name TEXT NOT NULL CHECK (btrim(canonical_name) <> ''),
    normalized_name TEXT NOT NULL CHECK (btrim(normalized_name) <> ''),
    category TEXT NOT NULL CHECK (
        category IN ('建筑构件', '器物', '纹样', '展品', '空间', '其他')
    ),
    summary TEXT NOT NULL CHECK (btrim(summary) <> ''),
    detail TEXT NOT NULL DEFAULT '',
    time_period TEXT NOT NULL DEFAULT '',
    region TEXT NOT NULL DEFAULT '',
    artwork_symbol TEXT NOT NULL CHECK (btrim(artwork_symbol) <> ''),
    status TEXT NOT NULL CHECK (status IN ('imported', 'reviewed', 'archived')),
    content_version BIGINT NOT NULL DEFAULT 1 CHECK (content_version > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (catalog_version, normalized_name)
);

CREATE INDEX knowledge_nodes_catalog_status_idx
    ON knowledge_nodes (catalog_version, node_type, status, canonical_name);

CREATE TABLE knowledge_aliases (
    id UUID PRIMARY KEY,
    node_id UUID NOT NULL
        REFERENCES knowledge_nodes(id)
        ON DELETE CASCADE,
    alias_text TEXT NOT NULL CHECK (btrim(alias_text) <> ''),
    normalized_alias TEXT NOT NULL CHECK (btrim(normalized_alias) <> ''),
    locale TEXT NOT NULL DEFAULT 'zh' CHECK (btrim(locale) <> ''),
    sort_order INTEGER NOT NULL CHECK (sort_order >= 0),
    UNIQUE (normalized_alias, locale),
    UNIQUE (node_id, sort_order)
);

CREATE INDEX knowledge_aliases_node_idx ON knowledge_aliases (node_id);

CREATE TABLE knowledge_geographies (
    node_id UUID NOT NULL
        REFERENCES knowledge_nodes(id)
        ON DELETE CASCADE,
    geography_kind TEXT NOT NULL CHECK (geography_kind IN ('region_code', 'city')),
    value TEXT NOT NULL CHECK (btrim(value) <> ''),
    normalized_value TEXT NOT NULL CHECK (btrim(normalized_value) <> ''),
    sort_order INTEGER NOT NULL CHECK (sort_order >= 0),
    PRIMARY KEY (node_id, geography_kind, normalized_value),
    UNIQUE (node_id, geography_kind, sort_order)
);

CREATE INDEX knowledge_geographies_lookup_idx
    ON knowledge_geographies (geography_kind, normalized_value, node_id);

CREATE TABLE knowledge_sources (
    id UUID PRIMARY KEY,
    title TEXT NOT NULL CHECK (btrim(title) <> ''),
    publisher TEXT NOT NULL CHECK (btrim(publisher) <> ''),
    url TEXT NOT NULL DEFAULT ''
);

CREATE TABLE node_sources (
    node_id UUID NOT NULL
        REFERENCES knowledge_nodes(id)
        ON DELETE CASCADE,
    source_id UUID NOT NULL
        REFERENCES knowledge_sources(id)
        ON DELETE RESTRICT,
    evidence_note TEXT NOT NULL DEFAULT '',
    sort_order INTEGER NOT NULL CHECK (sort_order >= 0),
    PRIMARY KEY (node_id, source_id),
    UNIQUE (node_id, sort_order)
);

CREATE INDEX node_sources_source_idx ON node_sources (source_id);

---- create above / drop below ----

DROP TABLE node_sources;
DROP TABLE knowledge_sources;
DROP TABLE knowledge_geographies;
DROP TABLE knowledge_aliases;
DROP TABLE knowledge_nodes;
DROP TABLE knowledge_catalogs;
