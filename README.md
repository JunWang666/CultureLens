# CultureLens

Monorepo for CultureLens: an iOS culture exploration app and its Go recognition / knowledge BFF.

## Layout

| Path | Description |
| --- | --- |
| [`CultureLens/`](CultureLens/) | SwiftUI iOS app (scan, explore, knowledge graph, history) |
| [`CultureLensBackend/`](CultureLensBackend/) | Go recognition BFF, PostgreSQL cultural content APIs, admin tooling |

## Quick start

### Backend

```bash
cd CultureLensBackend
# see CultureLensBackend/README.md for Postgres, .env, and mock recognition
MOCK_RECOGNITION=true go run ./cmd/api
```

### iOS

Open `CultureLens/CultureLens.xcodeproj` in Xcode and run the `CultureLens` scheme.

Agent design notes and project status live under `CultureLens/agents/`.
