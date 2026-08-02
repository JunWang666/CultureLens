# CultureLens

Monorepo for CultureLens: a SwiftUI iOS app (`CultureLens/`) and its Go recognition/knowledge BFF (`CultureLensBackend/`).

## Cursor Cloud specific instructions

Standard build/test/run commands are documented in `README.md` and `CultureLensBackend/README.md`; prefer those. Notes below are the non-obvious bits for working in this Linux cloud environment.

### Scope on this environment
- Only the **Go backend** (`CultureLensBackend/`) runs here. The `CultureLens/` iOS app requires macOS + Xcode and cannot be built or run on this Linux VM. The iOS app's API base URL is hardcoded to production, so it is not wired to a local backend.
- Toolchain baked into the VM snapshot: Go 1.25 (at `/usr/local/go`, symlinked into `/usr/local/bin/go`) and PostgreSQL 16 (native `apt` install). The `go mod download` refresh is handled by the startup update script.

### PostgreSQL (must be started each session)
The DB is required — recognition returns `503 recognition_unavailable` on any DB query failure, and knowledge routes read from it. The cluster is not auto-started on boot:

```bash
sudo pg_ctlcluster 16 main start
```

A dev role/database already exist in the snapshot: role `culturelens` / password `development-only`, database `culturelens` (owner), reachable over TCP at `127.0.0.1:5432`. Use this connection string:

```bash
export DATABASE_URL='postgres://culturelens:development-only@127.0.0.1:5432/culturelens?sslmode=disable'
```

If the role/db are ever missing, recreate with:
```bash
sudo -u postgres psql -c "CREATE ROLE culturelens LOGIN PASSWORD 'development-only' CREATEDB;"
sudo -u postgres createdb -O culturelens culturelens
```

### Migrations and content
- Apply schema (idempotent; re-runnable): `go run ./cmd/db up` (with `DATABASE_URL` set). `up` == `migrate`.
- Migrations 004/006 only grant privileges to the optional `culturelens_editor`/`culturelens_app` roles *if they exist*; in this single-role dev setup those blocks are safely skipped.
- Importing the reviewed content bundle is a separate admin op and requires `CULTURELENS_ADMIN_DATABASE_URL` (an editor-role URL). In dev, the `culturelens` owner role has full privileges, so reuse the same URL:
  ```bash
  export CULTURELENS_ADMIN_DATABASE_URL="$DATABASE_URL"
  go run ./cmd/content import   # loads content/hangzhou-west-lake bundle
  ```

### Running the API
Run in mock mode to avoid the external Gemini dependency (no API key needed):
```bash
MOCK_RECOGNITION=true go run ./cmd/api   # listens on :8080, needs DATABASE_URL
```
Mock mode still runs the full validation + DB retrieval + audit-write pipeline; only the external model call is stubbed. An empty `cultural_elements` table is a valid open-set state (still returns 200), so `503` means a real DB failure.

### Lint / test / build
- Vet (lint): `go vet ./...`
- Tests: `go test ./...` (all tests pass without a running DB — they use in-memory repositories)
- Build: `go build ./...`
