# Testbed

Design notes. Grows each phase.

## Decisions (P1)
- **Shared instrumentation** (`testbed/services/_shared`): every service gets identical metric names and log keys, so one PromQL/LogQL template works for all. `setup(app)` registers /health and /metrics itself, before service routes, so behaviour knobs (which live inside handlers) can't break the measuring equipment.
- **No fault switch.** Behaviour changes come from ordinary-looking knobs (env tuning), traffic patterns, DB changes, or deploying a different version. Nothing in logs, metrics, labels or k8s objects names a fault.
- **Version integrity.** Image tag = `<service>:<semver>`. `make build` stores a hash of the service dir + `_shared` in the image and refuses to rebuild the same tag with different code. Deployments carry `app.kubernetes.io/version` and a `demo-shop/git-sha` annotation (read from the image label).
- **Context guard.** Makefile and `scenarios/guard.sh` refuse to run unless kubectl context is `kind-pagerpilot`; all kubectl calls also pass `--context`.
- **Ground truth lives in `evals/scenarios/`, never under `testbed/`.**

## Metrics (all services)
`http_requests_total`, `http_request_duration_seconds` {method,route,status}; `app_build_info{version,git_sha}=1`; default process metrics. Unmatched routes: `route="unmatched"`.

## Log schema (JSON, stdout)
`time, level, service, version, request_id, message, method, path, status, duration_ms, user_agent`, plus `error:{code,message}` on 5xx. /health and /metrics are not logged.

## Topology (P2, ns demo)
frontend :3000 -> orders :3001 -> postgres :5432. `frontend` routes: `/checkout` (creates an order), `/orders/:id`, `/customers/:id/orders` (indexed lookup on customer_id; added so a frontend alert can trace to a slow index). `UPSTREAM_TIMEOUT_MS` and `ORDERS_URL` are env config.

`orders`: pg Pool max 10, connect timeout 2s, query timeout 5s. Queries >300ms log `slow query <n>ms on orders`. `POST /reports/export` runs an aggregate then holds its connection for `EXPORT_HOLD_MS` (4s) while the result is "written out". Orders keeps a never-evicted per-session lookup map (`x-session-id`), latent until traffic carries many unique session ids.

`orders` metrics: `db_pool_connections{state}`, `db_query_duration_seconds{query}` (query time only, excludes pool wait). `frontend` metrics: `upstream_requests_total`, `upstream_request_duration_seconds` {upstream,status}; status is the HTTP code, `timeout` or `error`.

Postgres: `postgres:16-alpine`, trust auth + emptyDir (local kind only, no secrets). Init script seeds 500k orders over 5000 customers with `idx_orders_customer_id`. A fresh pod re-seeds (~20s).
