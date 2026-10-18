#!/usr/bin/env bash
# verify.sh: is the testbed at a healthy baseline? Exits non-zero on the first failed check.
# SLO_WINDOW (default 5m) is the lookback for latency and error checks.
set -euo pipefail
. "$(dirname "$0")/../scenarios/lib.sh"   # guard (context check), $K, prom_count
W=${SLO_WINDOW:-5m}

pass() { echo "ok    $*"; }
fail() { echo "FAIL  $*" >&2; exit 1; }
lt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0 < b+0)}'; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0 > b+0)}'; }

pass "context $EXPECTED_CONTEXT"

$K -n demo wait --for=condition=Ready pod -l app.kubernetes.io/part-of=demo-shop --timeout=120s >/dev/null \
  || fail "demo pods not all Ready"
$K -n platform wait --for=condition=Ready pod -l app=alert-echo --timeout=60s >/dev/null || fail "alert-echo not Ready"
pass "all pods Ready"

n=$($K -n demo exec deploy/postgres -- psql -U postgres -d shop -tAc 'select count(*) from orders')
[ "$n" -ge 500000 ] || fail "orders table has $n rows (expected >= 500000); try make reset"
pass "orders seeded ($n rows)"

total=$(prom_count 'count(up{namespace="demo"}) or vector(0)')
up=$(prom_count 'count(up{namespace="demo"} == 1) or vector(0)')
{ [ "$total" = "$up" ] && [ "$total" -ge 2 ]; } || fail "demo targets up: $up of $total"
pass "all demo targets up=1 ($up)"

rate=$(prom_count "sum(rate(http_requests_total{namespace=\"demo\",service=\"frontend\",route!~\"/health|/metrics\"}[$W]))")
gt "$rate" 5 || fail "frontend request rate $rate rps (load generator not running?)"
for svc in frontend orders; do
  p95=$(prom_count "histogram_quantile(0.95, sum by (le)(rate(http_request_duration_seconds_bucket{namespace=\"demo\",service=\"$svc\",route!~\"/health|/metrics\"}[$W])))")
  lt "$p95" 0.15 || fail "$svc p95 ${p95}s over $W (limit 0.15s)"
done
pass "frontend rate ${rate%.*} rps, p95 < 150ms over $W"

errs=$(prom_count "sum(increase(http_requests_total{namespace=\"demo\",status=~\"5..\"}[$W])) or vector(0)")
lt "$errs" 1 || fail "$errs 5xx responses over $W"
pass "zero 5xx over $W"

firing=$(prom_count 'count(ALERTS{alertstate="firing",alertname!="Watchdog"}) or vector(0)')
pending=$(prom_count 'count(ALERTS{alertstate="pending",namespace="demo"}) or vector(0)')
[ "$firing" = "0" ] || fail "$firing unexpected alert(s) firing"
[ "$pending" = "0" ] || fail "$pending demo alert(s) pending"
pass "no unexpected alerts (only Watchdog)"

for app in frontend orders; do
  logql="sum(count_over_time({namespace=\"demo\",app=\"$app\"} | json | request_id != \"\" [5m]))"
  enc=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$logql")
  lines=$($K -n monitoring get --raw "/api/v1/namespaces/monitoring/services/pagerpilot-loki-gateway:80/proxy/loki/api/v1/query?query=$enc" \
    | jq -r '.data.result[0].value[1] // "0"')
  gt "$lines" 0 || fail "no $app logs with request_id in Loki over 5m"
done
pass "logs queryable in Loki (frontend, orders)"
echo "baseline healthy"
