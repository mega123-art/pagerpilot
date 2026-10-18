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

## Scenarios (P5)
Extra traffic comes from a Deployment `ext-client` (k6, ns demo) created by `inject.sh` and removed by `revert.sh`. Scripts: `testbed/scenarios/<id>/`. Ground truth: `evals/scenarios/<id>.yaml` (outside `testbed/` on purpose).

| scenario | trigger | settle (measured) | alerts | metrics | logs | deploys |
|---|---|---|---|---|---|---|
| memory_leak | 12 rps with unique session ids -> unbounded session map in orders | first OOM ~4.7 min; revert ~10 min | ContainerRestarting (memory alert only pending) | strong | weak | none |
| db_pool_exhaustion | 4 rps POST /reports/export, each holds a connection ~4s | ~2 min | HighErrorRate + HighLatencyP95 on orders and frontend | strong | strong | none |
| slow_query_missing_index | DROP INDEX on orders.customer_id + 8 rps order-history traffic | ~2-3 min | HighLatencyP95 on frontend and orders | strong | medium | none |

Notes
- Reverts wait for alerts to clear, so back-to-back runs start clean.
- The wider `notes` column (~190B/row), postgres `cpu: 500m` and orders `NODE_OPTIONS=--max-old-space-size=192` exist so these faults look the way they do in production: scans cost real time, and the leak ends in OOMKilled instead of a V8 heap abort.
- Baseline orders image is 1.0.2 (1.0.1 added the notes column, 1.0.2 the slow-export warning). bad_deploy will ship 1.1.0.

## Deploy-history scenarios (P6)
Source of `orders` and `frontend` lives in a separate public repo, **github.com/mega123-art/pagerpilot-demo-shop**, so this repo stays clean and the agent's deploys tool never sees ground truth. This repo only holds cluster manifests and scripts (`testbed/scripts/`): `make up` clones the repo into `testbed/.cache/`, builds each image from a release tag (`orders-v1.0.2`, `frontend-v1.0.0`), and deploys it. The git sha on every Deployment is the real commit in that repo.

- **Baseline history is backdated** (Sept 14 - Oct 1) so a no-deploy scenario never shows a "recent" commit. This is a test fixture, not a claim about real development dates.
- **bad_deploy** creates its evidence at inject time: applies `scenarios/bad_deploy/regression.diff` as two normal commits (`perf(orders): paginate order history by placed_at`, `chore(release): orders v1.1.0`), tags `orders-v1.1.0`, pushes, deploys the image, records a GitHub Deployment. The diff adds a `placed_at` sort and its migration in the same commit, but the migration is never applied, so the history query fails with Postgres 42703.
- **bad_config** commits `ORDERS_URL: http://orders:3002` to `deploy/frontend-config.yaml`, redeploys the frontend (config sha is a pod annotation) and records a Deployment. Orders doesn't listen on 3002, so frontend calls time out after 3s (504) and orders traffic drops to zero.
- **revert** for both: redeploy baseline, force-reset `main` to `orders-v1.0.2`, delete the `orders-v1.1.0` tag, delete all deployment records. Needs `gh` authenticated with `repo` scope. Anyone cloning the repo during a run sees the incident commits; they disappear on revert.

Measured: bad_deploy errors start at rollout, alerts after ~2 min, back to baseline 131s after revert. bad_config: alerts HighErrorRate + HighLatencyP95 (frontend) ~1.5 min after rollout, baseline 111s after revert.

## Caveats resolved / known
- Reverts now block (`wait_quiet`) until no demo alert is pending/firing, so the next run starts clean (`make settle` does the same on its own). memory_leak revert takes ~10 min because `ContainerRestarting` looks back 10 min.
- memory_leak: `ContainerMemoryHigh` goes pending but does not reliably fire (heap grows in bursts near the limit). A ramped/tapering load was tried and didn't make it reliable, so the scenario stays a constant 12 rps and `ContainerRestarting` is the expected alert.
- slow_query_missing_index also alerts on orders; the eval fixture for it uses the frontend alert.

## These services are intentionally insecure
No auth, `SELECT *`, a never-evicted session map, trust-auth Postgres. They are throwaway targets for incident scenarios and run only on the local kind cluster. Never deploy them anywhere reachable.
