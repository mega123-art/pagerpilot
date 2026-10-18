# Progress

## P1: template service refactor + Makefile (2026-10-18)
- `testbed/services/_shared`: one module for metrics, JSON logs, request ids, /health, /metrics.
- demo-api now uses it; FAULT_MODE removed (WORK_MIN_MS / WORK_MAX_MS are plain tuning knobs).
- Generic `services/Dockerfile` (context `testbed/services`), image `<service>:<semver>`.
- Single ServiceMonitor `demo-shop` selecting `app.kubernetes.io/part-of=demo-shop`.
- `testbed/Makefile` with context guard (`kind-pagerpilot` only). inject/revert/smoke are stubs until scenarios exist.
- Not yet verified against the cluster: Docker was not running at the time. Local node run verified metrics + log schema.
