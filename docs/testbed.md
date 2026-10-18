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
