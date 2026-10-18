# PagerPilot

An AI agent that investigates production alerts. It reads Prometheus metrics, Loki logs and GitHub deploy
history through read-only MCP tools, then posts a root-cause hypothesis.

This repo currently contains the **testbed**: a small shop running on a local kind cluster that can be
broken in five known ways, so the agent can be scored against a ground truth that is recorded outside
anything it can read.

## Testbed

```
frontend -> orders -> postgres        (ns demo, source: github.com/mega123-art/pagerpilot-demo-shop)
loadgen (k6, 8 req/s, open loop)
Prometheus + Alertmanager + Loki + Alloy + Grafana   (ns monitoring)
alert-echo (webhook receiver)                        (ns platform)
```

| scenario | what actually happened | metrics | logs | deploys |
|---|---|---|---|---|
| `memory_leak` | unbounded per-session map in orders, flood of unique sessions | strong | weak | none |
| `db_pool_exhaustion` | heavy export calls hold every pooled DB connection | strong | strong | none |
| `slow_query_missing_index` | `customer_id` index dropped; alert is on the frontend | strong | medium | none |
| `bad_deploy` | orders v1.1.0 queries a column whose migration never ran | onset | strong | decisive |
| `bad_config` | frontend `ORDERS_URL` pointed at a port nobody listens on | rate drop | strong | decisive |

Ground truth for each lives in [`evals/scenarios/`](evals/scenarios), never under `testbed/`.
Real alert payloads and timings from verified runs are in [`evals/fixtures/`](evals/fixtures).

### Run it

Requires Docker, kind (cluster named `pagerpilot`), kubectl, helm, jq, `gh` (authenticated, for the deploy
scenarios). Monitoring is installed with Helm from `testbed/monitoring/` (see [docs/testbed.md](docs/testbed.md)).

```bash
cd testbed
make up                      # build images, deploy the shop + load generator
make verify                  # healthy baseline? (pods, targets, SLOs, alerts, logs)
make smoke S=bad_deploy      # inject, wait for the alert, save its payload, revert, confirm recovery
make control                 # 15 minutes untouched; must produce zero alerts
make inject S=memory_leak    # or drive a scenario by hand ...
make revert S=memory_leak    # ... and undo it (blocks until alerts clear)
```

Every script refuses to run unless the kubectl context is `kind-pagerpilot`.

The services are intentionally insecure throwaways (no auth, a deliberate leak). Run them only on the local cluster.

More: [docs/testbed.md](docs/testbed.md) (topology, metric and log schema, evidence matrix, how to add a
scenario) and [docs/PROGRESS.md](docs/PROGRESS.md).
