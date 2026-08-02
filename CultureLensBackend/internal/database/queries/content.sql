-- name: UpsertCulturalElement :one
INSERT INTO cultural_elements (
    key,
    name,
    introduction
) VALUES (
    sqlc.arg(element_key),
    sqlc.arg(name),
    sqlc.arg(introduction)
)
ON CONFLICT (key) DO UPDATE SET
    name = EXCLUDED.name,
    introduction = EXCLUDED.introduction,
    updated_at = now()
RETURNING key, name, introduction, created_at, updated_at;

-- name: GetCulturalElement :one
SELECT key, name, introduction, created_at, updated_at
FROM cultural_elements
WHERE key = sqlc.arg(element_key);

-- name: ListCulturalElements :many
SELECT key, name, introduction, created_at, updated_at
FROM cultural_elements
ORDER BY name, key;

-- name: InsertCulturalElementRelation :exec
INSERT INTO cultural_element_relations (
    element_key,
    related_element_key
) VALUES (
    sqlc.arg(element_key),
    sqlc.arg(related_element_key)
);

-- name: UpsertCulturalElementRelation :exec
INSERT INTO cultural_element_relations (
    element_key,
    related_element_key
) VALUES (
    sqlc.arg(element_key),
    sqlc.arg(related_element_key)
)
ON CONFLICT DO NOTHING;

-- name: ListCulturalElementRelations :many
SELECT
    LEAST(element_key, related_element_key)::text AS element_key,
    GREATEST(element_key, related_element_key)::text AS related_element_key
FROM cultural_element_relations
ORDER BY element_key, related_element_key;

-- name: DeleteCulturalElementRelation :exec
DELETE FROM cultural_element_relations
WHERE LEAST(element_key, related_element_key) = LEAST(
        sqlc.arg(element_key)::text,
        sqlc.arg(related_element_key)::text
    )
  AND GREATEST(element_key, related_element_key) = GREATEST(
        sqlc.arg(element_key)::text,
        sqlc.arg(related_element_key)::text
    );

-- name: ListRelatedCulturalElements :many
SELECT
    related.key,
    related.name,
    related.introduction,
    related.created_at,
    related.updated_at
FROM cultural_element_relations AS relation
JOIN cultural_elements AS related
  ON related.key = CASE
      WHEN relation.element_key = sqlc.arg(element_key)
      THEN relation.related_element_key
      ELSE relation.element_key
  END
WHERE relation.element_key = sqlc.arg(element_key)
   OR relation.related_element_key = sqlc.arg(element_key)
ORDER BY related.name, related.key
LIMIT sqlc.arg(related_limit);

-- name: GetCulturalContentStats :one
SELECT
    (SELECT count(*) FROM cultural_elements) AS cultural_element_count,
    (SELECT count(*) FROM attraction_cultural_introductions) AS introduction_count;

-- name: UpsertAttraction :one
INSERT INTO attractions (
    key,
    name
) VALUES (
    sqlc.arg(attraction_key),
    sqlc.arg(name)
)
ON CONFLICT (key) DO UPDATE SET
    name = EXCLUDED.name,
    updated_at = now()
RETURNING key, name, created_at, updated_at;

-- name: GetAttraction :one
SELECT key, name, created_at, updated_at
FROM attractions
WHERE key = sqlc.arg(attraction_key);

-- name: ListAttractions :many
SELECT key, name, created_at, updated_at
FROM attractions
ORDER BY name, key;

-- name: UpsertAttractionCulturalIntroduction :one
INSERT INTO attraction_cultural_introductions (
    key,
    name,
    introduction,
    cultural_element_key,
    attraction_key,
    latitude,
    longitude
) VALUES (
    sqlc.arg(introduction_key),
    sqlc.arg(name),
    sqlc.arg(introduction),
    sqlc.arg(cultural_element_key),
    sqlc.arg(attraction_key),
    sqlc.arg(latitude),
    sqlc.arg(longitude)
)
ON CONFLICT (key) DO UPDATE SET
    name = EXCLUDED.name,
    introduction = EXCLUDED.introduction,
    cultural_element_key = EXCLUDED.cultural_element_key,
    attraction_key = EXCLUDED.attraction_key,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    updated_at = now()
RETURNING
    key,
    name,
    introduction,
    cultural_element_key,
    attraction_key,
    latitude,
    longitude,
    created_at,
    updated_at;

-- name: GetAttractionCulturalIntroduction :one
SELECT
    introduction.key,
    introduction.name,
    introduction.introduction,
    introduction.cultural_element_key,
    element.name AS cultural_element_name,
    introduction.attraction_key,
    attraction.name AS attraction_name,
    introduction.latitude,
    introduction.longitude,
    introduction.created_at,
    introduction.updated_at
FROM attraction_cultural_introductions AS introduction
JOIN cultural_elements AS element
  ON element.key = introduction.cultural_element_key
JOIN attractions AS attraction
  ON attraction.key = introduction.attraction_key
WHERE introduction.key = sqlc.arg(introduction_key);

-- name: ListAttractionCulturalIntroductions :many
SELECT
    introduction.key,
    introduction.name,
    introduction.introduction,
    introduction.cultural_element_key,
    element.name AS cultural_element_name,
    introduction.attraction_key,
    attraction.name AS attraction_name,
    introduction.latitude,
    introduction.longitude,
    introduction.created_at,
    introduction.updated_at
FROM attraction_cultural_introductions AS introduction
JOIN cultural_elements AS element
  ON element.key = introduction.cultural_element_key
JOIN attractions AS attraction
  ON attraction.key = introduction.attraction_key
WHERE introduction.attraction_key = sqlc.arg(attraction_key)
ORDER BY introduction.name, introduction.key;

-- name: ListAllAttractionCulturalIntroductions :many
SELECT
    introduction.key,
    introduction.name,
    introduction.introduction,
    introduction.cultural_element_key,
    element.name AS cultural_element_name,
    introduction.attraction_key,
    attraction.name AS attraction_name,
    introduction.latitude,
    introduction.longitude,
    introduction.created_at,
    introduction.updated_at
FROM attraction_cultural_introductions AS introduction
JOIN cultural_elements AS element
  ON element.key = introduction.cultural_element_key
JOIN attractions AS attraction
  ON attraction.key = introduction.attraction_key
ORDER BY introduction.name, introduction.key;

-- name: ListNearbyAttractionCulturalIntroductions :many
WITH request AS (
    SELECT
        sqlc.arg(latitude)::double precision AS latitude,
        sqlc.arg(longitude)::double precision AS longitude,
        sqlc.arg(radius_meters)::double precision AS radius_meters
),
distances AS (
    SELECT
        introduction.key,
        introduction.name,
        introduction.introduction,
        introduction.cultural_element_key,
        element.name AS cultural_element_name,
        introduction.attraction_key,
        attraction.name AS attraction_name,
        introduction.latitude,
        introduction.longitude,
        CAST(6371008.8 * 2 * asin(
            LEAST(
                1.0,
                sqrt(
                    power(
                        sin(radians(introduction.latitude - request.latitude) / 2),
                        2
                    ) +
                    cos(radians(request.latitude)) *
                    cos(radians(introduction.latitude)) *
                    power(
                        sin(radians(introduction.longitude - request.longitude) / 2),
                        2
                    )
                )
            )
        ) AS double precision) AS distance_meters
    FROM attraction_cultural_introductions AS introduction
    JOIN cultural_elements AS element
      ON element.key = introduction.cultural_element_key
    JOIN attractions AS attraction
      ON attraction.key = introduction.attraction_key
    CROSS JOIN request
)
SELECT
    distances.key,
    distances.name,
    distances.introduction,
    distances.cultural_element_key,
    distances.cultural_element_name,
    distances.attraction_key,
    distances.attraction_name,
    distances.latitude,
    distances.longitude,
    distances.distance_meters,
    count(*) OVER () AS total_matches
FROM distances
CROSS JOIN request
WHERE distances.distance_meters <= request.radius_meters
ORDER BY distances.distance_meters, distances.name, distances.key
LIMIT sqlc.arg(result_limit);
