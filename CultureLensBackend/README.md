# CultureLens Go recognition BFF

The service keeps Google AI Studio keys off the Apple client, preserves the iOS
recognition contract, and exposes read-only reviewed cultural knowledge APIs.

## Run locally

```bash
cd CultureLensBackend
docker run --rm --name culturelens-postgres-dev \
  --publish 127.0.0.1:5432:5432 \
  --env POSTGRES_DB=culturelens \
  --env POSTGRES_USER=culturelens \
  --env POSTGRES_PASSWORD=development-only \
  postgres:18.4-alpine

export DATABASE_URL='postgres://culturelens:development-only@127.0.0.1:5432/culturelens?sslmode=disable'
go run ./cmd/db up
MOCK_RECOGNITION=true go run ./cmd/api
curl http://127.0.0.1:8080/health
go test ./...
```

Mock mode executes the complete validation and response-mapping pipeline without
an external model request. For real recognition, set `MOCK_RECOGNITION=false`,
`GOOGLE_AI_STUDIO_API_KEYS` (comma-separated). The service loads the local, Git-ignored `.env` file
automatically and calls Google AI Studio's Gemini `generateContent` API using
`gemini-3.6-flash` with the `recognition-v5` prompt/schema. The optional `focus_image_base64` request field lets the App send
a user-selected close-up beside the full scene; the provider treats the close-up as
the primary evidence and still returns one primary plus up to three alternatives.

Recognition now uses the production cultural-content model. The runtime
`RecognitionKnowledgeRepository` reads at most 12 candidates from `cultural_elements` and,
when a recorded or current location is present, attaches nearby `attraction_cultural_introductions` as
place context without sending coordinates to Gemini. Gemini may return a retrieved stable
`cultural_element_key` or an unresolved outside-content result; it cannot claim a key that
was not retrieved. For resolved results, the name and introduction come from PostgreSQL.
An empty cultural-element table is a valid open-set recognition state and still calls the
provider; only an actual PostgreSQL query failure returns `503 recognition_unavailable`.

The migration-1/2 reviewed-catalog model has been retired. Runtime code, sqlc queries,
fixtures, and seed commands no longer reference the removed `knowledge_*`, `node_sources`,
or `edge_sources` tables. Current cultural content lives only in the four cultural-element
and attraction tables created by migration 3.

Apply schema migrations without importing any content:

```bash
DATABASE_URL="$DATABASE_URL" go run ./cmd/db up
```

`up` and `migrate` are equivalent. SQL queries are generated with sqlc 1.31.1 and pgx/v5:

```bash
go run github.com/sqlc-dev/sqlc/cmd/sqlc@v1.31.1 generate
```

## API documentation

Huma v2 generates the OpenAPI specification from the Go request and response
types and serves an interactive Stoplight Elements reference:

- Production reference: `https://cl.codight.online/docs`
- OpenAPI 3.1: `https://cl.codight.online/openapi.json` or `/openapi.yaml`
- OpenAPI 3.0.3 compatibility: `/openapi-3.0.json` or `/openapi-3.0.yaml`
- Individual JSON Schemas: `/schemas/{schema}.json`

The real `GET /health` and `POST /v1/recognitions` handlers remain on the
existing `net/http` path so the iOS JSON and error contracts are unchanged.
The documentation's Try It requests use the production server declared in the
generated OpenAPI document.

The read-only knowledge routes are:

```http
GET /v1/cultural-elements/{elementKey}/related?limit=12
GET /v1/attraction-introductions/recommendations?latitude=30.248963&longitude=120.148691&radiusMeters=5000&limit=12
```

The first route reads explicit undirected relations from `cultural_element_relations`
using stable text keys. The second reads `attraction_cultural_introductions` and computes
WGS84 Haversine distance from the requested coordinate. It only returns introductions
inside the requested radius, ordered by distance, and never falls back to unrelated
content. Rich-text introductions remain JSON documents in the response.

## Debug UI

Open `/debug` on the running backend, for example
`http://127.0.0.1:8080/debug`. The single-page debug console can call both knowledge
routes and displays the request URL, HTTP status, elapsed time, `X-Request-ID`, and
formatted JSON response. It is embedded in the Go binary, has no separate frontend
build, sends requests only to the current origin, and does not persist form values.

## Content admin UI

Open `/admin` to edit cultural elements, attractions, attraction-specific introductions,
relations, and exact coordinates. Management is enabled when the server-only
`CULTURELENS_ADMIN_DATABASE_URL` is configured. The editor database role should have only
`SELECT/INSERT/UPDATE` on the four content tables.

Open `/admin/recognitions` for the latest 100 recognition requests. Every recognition
attempt is recorded, including failures. Valid requests retain the context image, optional
focus image, location/context metadata, public response or error envelope, HTTP status,
model versions, and elapsed time. Images are loaded only when an audit row is expanded;
the list endpoint never embeds image bytes. Invalid JSON requests retain their byte count
and result but not arbitrary unparsed content. The runtime role has `INSERT` only on
`recognition_request_logs`, while the editor role has `SELECT` only. Audit history is not
automatically pruned yet, so production storage and retention must be monitored.

The application does not implement a
second management token: production access to `/admin` and `/v1/admin/*` is protected by
Cloudflare Zero Trust. Keep the origin unreachable from the public internet except through
that access policy. Admin routes are intentionally not included in the public OpenAPI document.

The reviewed starter bundle at `content/hangzhou-west-lake.v1.json` contains original
short descriptions for seven West Lake attractions and records a coordinate source URL
for each introduction. Importing it is an explicit management operation; normal
migrations never load content.

## Build the Silk Road research knowledge base

The separate research bundle collects factual collection metadata from the public
Silk Road Online Museum (linked by IIDOS) and fixed-revision Chinese Wikipedia
topics:

```bash
go run ./cmd/knowledge sync
go run ./cmd/knowledge validate \
  -file knowledge/bundles/silk-road.v1.json
go run ./cmd/knowledge query \
  -file knowledge/bundles/silk-road.v1.json \
  -q 丝绸
```

The generated records stay `imported`; they are not automatically added to the
three-object reviewed recognition catalog. SROM long-form descriptions and image
files are not copied. Wikipedia records retain revision IDs, attribution URLs, and
CC BY-SA 4.0 metadata. See `knowledge/README.md` for the rights and review boundary.

When Google returns HTTP 429, it retries with the next
configured key in declaration order; all other failures return immediately.

The iOS target receives an HTTPS service URL via `CULTURELENS_API_BASE_URL`.
Never put Google AI Studio API keys in the app, scheme arguments, UserDefaults, or
SwiftData. Authentication, rate limiting, reviewed knowledge-graph retrieval,
and a production retention policy remain later phases from Design 0005.

## Build and run the Docker image

Build the production image for a typical Linux server:

```bash
docker build \
  --platform linux/amd64 \
  --tag ccr.ccs.tencentyun.com/gouzuang/culturelens:latest \
  .
```

Run a local smoke test without calling the external model:

```bash
docker run --rm \
  --platform linux/amd64 \
  --publish 8080:8080 \
  --env MOCK_RECOGNITION=true \
  ccr.ccs.tencentyun.com/gouzuang/culturelens:latest
```

For production, inject `GOOGLE_AI_STUDIO_API_KEYS` and the other values from
`.env.example`. `DATABASE_URL` remains read-only for cultural content and has only the
additional `INSERT` privilege required for recognition audit rows. Inject it through the deployment
platform at container start. Before starting the API, run the bundled migration
binary with an administrator connection:

```bash
docker run --rm \
  --network culturelens-db \
  --env-file /opt/culturelens/database-admin.env \
  --entrypoint ./culturelens-db \
  ccr.ccs.tencentyun.com/gouzuang/culturelens:latest \
  up
```

Migration 3 creates `cultural_elements`, `cultural_element_relations`, `attractions`,
and `attraction_cultural_introductions`. Migration 4 conditionally grants an existing
`culturelens_editor` role `SELECT/INSERT/UPDATE` on only those tables. Verify both the
read-only application grant and editor grant before switching the API container.

Do not pass credentials as Docker build arguments or copy `.env` into the image. The
service runs as UID/GID `10001`, listens on `PORT` (default `8080`), and exposes a
Docker health check backed by `GET /health`.

## Evaluate recognition quality

`cmd/eval` runs the production pipeline against an authorized JSONL dataset. Use the
same dataset to compare `whole`, `crop`, and `context-focus` image strategies:

```bash
go run ./cmd/eval \
  -dataset evals/datasets/culture-v1.jsonl \
  -dataset-version culture-v1 \
  -strategy context-focus \
  -location-context dataset \
  -output evals/reports/context-focus.json
```

Run the same command with `-location-context off` to create a paired no-location
control report. Reports include repository location effects, catalog version,
candidate counts, and the resolved result rate.

See `evals/datasets/README.md` for the dataset format and privacy boundary.
