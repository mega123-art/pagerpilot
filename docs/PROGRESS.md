# Progress

## P1: template service refactor + Makefile (2026-10-18)
- `testbed/services/_shared`: one module for metrics, JSON logs, request ids, /health, /metrics.
- demo-api now uses it; FAULT_MODE removed (WORK_MIN_MS / WORK_MAX_MS are plain tuning knobs).
- Generic `services/Dockerfile` (context `testbed/services`), image `<service>:<semver>`.
- Single ServiceMonitor `demo-shop` selecting `app.kubernetes.io/part-of=demo-shop`.
- `testbed/Makefile` with context guard (`kind-pagerpilot` only). inject/revert/smoke are stubs until scenarios exist.
- Not yet verified against the cluster: Docker was not running at the time. Local node run verified metrics + log schema.

## P2: postgres, orders, frontend (2026-10-18)
- Added orders 1.0.0, frontend 1.0.0, postgres 16 (500k seeded rows, idx on customer_id). Removed demo-api.
- Verified: all targets up=1; `/checkout` creates an order, `/orders/:id` reads it; same request_id in frontend and orders Loki logs.
- P1 verified on cluster first (Prometheus service name in `make verify` fixed).

## P3: k6 open-loop load generator (2026-10-18)
- `testbed/loadgen/baseline.js` in ConfigMap `loadgen-scripts`; Deployment `loadgen` (grafana/k6:0.55.0, arm64). constant-arrival-rate 8/s: 30% /checkout, 40% /orders/:id, 30% /customers/:id/orders; 200 session ids.
- 15 min soak: 8 rps on each of frontend/orders, p95 frontend 9ms / orders 5ms, zero 5xx, zero restarts.
- Only firing alerts are Watchdog and kube-etcd/scheduler/controller-manager/proxy target-down (kind has no scrapeable control plane). Fixed in P4 by disabling those components.
- Fixes folded in: orders initContainer waits for postgres; `make verify` checks seed; build hash ignores `k8s/` manifests.

## P4: alerting (2026-10-18)
- Chart values verified with `helm show values` (kube-prometheus-stack 92.10.1): disabled kubeControllerManager/kubeScheduler/kubeProxy/kubeEtcd and their defaultRules; Alertmanager routing via `alertmanager.config`.
- `monitoring/rules/demo-shop.yaml`: HighErrorRate, HighLatencyP95, ContainerRestarting, ContainerMemoryHigh (labels service/namespace/severity; symptom-only descriptions; dashboard_url -> Grafana dashboard `demo-shop`, `monitoring/dashboard.yaml`).
- Alertmanager: group_by [alertname, service], 10s/1m/1h, send_resolved; namespace="demo" -> webhook `alert-echo` (ns platform), everything else -> `null`.
- Verified: all 4 rules health=ok; under load only Watchdog fires; manual alert (namespace=demo) reached alert-echo, a kube-system one did not.
- `make monitoring` applies the Helm values. dashboard_url assumes `kubectl -n monitoring port-forward svc/pagerpilot-monitoring-grafana 3000:80`.

## P5: scenarios without deploy history (2026-10-18)
- memory_leak, db_pool_exhaustion, slow_query_missing_index: inject/revert scripts (idempotent, tested twice), `ext-client` traffic source, ground truth in `evals/scenarios/`.
- Tuned on the live cluster: leak 20->12 rps (OOM in ~4.7 min instead of ~3); export 6->4 rps (still saturates the pool, less than total outage); table widened and postgres CPU-limited, since a missing index cost only 6ms on the 32MB table.
- orders 1.0.1 (notes column) and 1.0.2 (slow-export warn log). Postgres reseeded.
- Known: slow_query also alerts on orders (not only frontend); memory alert does not fire in memory_leak.

## P6: deploy-history scenarios (2026-10-18)
- Created public repo mega123-art/pagerpilot-demo-shop (orders, frontend, shared, migrations, frontend config); testbed now builds images from its release tags. Baseline history backdated Sept-Oct 1.
- bad_deploy (orders v1.1.0, unapplied migration -> 42703 on order history) and bad_config (ORDERS_URL -> :3002 -> frontend timeouts). Both inject/revert tested; GitHub Deployment recorded at inject and removed on revert; repo reset to baseline.
- `wait_quiet` in every revert, `make settle`. Memory alert caveat documented (ramp tried, reverted).
- Ground truth in evals/scenarios/{bad_deploy,bad_config}.yaml.

## P7: verification and docs (2026-10-18)
- `make verify` (context, pods, seed, targets, SLOs, alerts, Loki), `make smoke S=<id>`, `make control`.
- smoke passes for all five scenarios; payloads and timings saved under `evals/fixtures/`. Control run: 15 min, zero alerts.
- smoke waits for a clean baseline before injecting (the first batch aborted because a 5m SLO window still held the previous incident).
- README, evidence matrix, how-to-add-a-scenario, measured timings in docs/testbed.md.
