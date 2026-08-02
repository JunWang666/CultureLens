# CultureLens PostgreSQL

Production currently runs PostgreSQL as a standalone Docker container on the
CultureLens VM. The deployment contract is:

```text
image:      postgres:18.4-alpine
container:  culturelens-postgres
networks:   bridge + culturelens-db (internal)
volume:     culturelens-postgres-data
database:   culturelens
admin role: culturelens_admin
app role:   culturelens_app
```

Port 5432 is published on the VM for trusted-network debugging. Connect to
`192.168.3.138:5432` from the LAN or `10.0.0.108:5432` from the PVE internal
network. The API container should still use the `culturelens-postgres` Docker
DNS name after joining `culturelens-db`.

This port publication does not configure router forwarding or a Cloudflare TCP
tunnel. Do not expose the non-TLS PostgreSQL endpoint directly to the internet.
The container must remain attached to `bridge` for the host port mapping and to
`culturelens-db` for the stable internal DNS name. An internal-only attachment
does not create an effective host listener even if `-p 5432:5432` is present.

Server-only configuration lives under `/opt/culturelens`:

```text
postgres.env
postgres-admin-password
postgres-app-password
database-admin.env
database.env
database-editor.env
```

These files must remain owned by `root:root` with mode `0600`. Never copy them
into this repository or a Docker image. `database-admin.env` is only for
`culturelens-db up`; the API consumes `database.env` and its read-only
`culturelens_app` connection. When content management is enabled, the API also consumes
`database-editor.env`, which remains root-only. The application does not use a management
token; Cloudflare Zero Trust protects the public management entry point. The editor role has no
schema, role, database, legacy knowledge-table, or delete permission.

For PostgreSQL 18 and later, persist the volume at `/var/lib/postgresql` and use
the versioned `PGDATA=/var/lib/postgresql/18/docker`. Do not change the mount to
the pre-18 `/var/lib/postgresql/data` convention.

Operational checks:

```sh
docker inspect --format '{{.State.Health.Status}}' culturelens-postgres
docker exec culturelens-postgres pg_isready -U culturelens_admin -d culturelens
docker exec culturelens-postgres psql -U culturelens_admin -d culturelens -c 'SELECT version();'
docker exec culturelens-postgres psql -U culturelens_admin -d culturelens -c \
  'SELECT count(*) FROM cultural_elements;'
```

The production application image bundles `culturelens-db`. Run migrations before
replacing the API; `up` does not import or seed any content:

```sh
docker run --rm \
  --network culturelens-db \
  --env-file /opt/culturelens/database-admin.env \
  --entrypoint ./culturelens-db \
  ccr.ccs.tencentyun.com/gouzuang/culturelens:latest \
  up
```

Migration 3 adds `cultural_elements`, `cultural_element_relations`, `attractions`, and
`attraction_cultural_introductions`. It conditionally grants `culturelens_app` `SELECT`
when that role exists. Migration 4 conditionally grants `culturelens_editor` only
`SELECT/INSERT/UPDATE` on those four tables. Create the role before migration 4, then
verify the new tables and grants before replacing the API:

```sh
docker exec culturelens-postgres psql -U culturelens_admin -d culturelens -c \
  '\dp cultural_elements'
docker exec culturelens-postgres psql -U culturelens_admin -d culturelens -c \
  '\dp attraction_cultural_introductions'
```

The production VM uses this Docker Hub registry mirror:

```text
https://2i4cjmb0k3zjbpwjri.xuanyuan.run
```

It is configured in `/etc/docker/daemon.json`. The deployed
`postgres:18.4-alpine` repository digest is
`sha256:9a8afca54e7861fd90fab5fdf4c42477a6b1cb7d293595148e674e0a3181de15`.

Before storing production knowledge data, add automated backups and perform a
restore test. Do not delete `culturelens-postgres-data` during routine container
replacement.
