#!/usr/bin/env bash
# control.sh [seconds]: no change to the system for N seconds (default 900); there must be zero
# alerts. Proves the alert rules don't fire on healthy load (no false positives).
# Writes evals/fixtures/runs/control.json.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../scenarios/lib.sh"
dur=${1:-900}
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$ROOT/evals/fixtures/runs/control.json"
mkdir -p "$(dirname "$OUT")"

"$HERE/verify.sh" >/dev/null || { echo "baseline not healthy; run make verify" >&2; exit 1; }
start=$(date -u +%Y-%m-%dT%H:%M:%SZ); t0=$SECONDS; seen=0
while [ $((SECONDS - t0)) -lt "$dur" ]; do
  n=$(prom_count 'count(ALERTS{alertname!="Watchdog"}) or vector(0)')
  [ "$n" = "0" ] || { seen=$n; echo "unexpected alert(s) after $((SECONDS - t0))s" >&2; break; }
  sleep 15
done
end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# anything that fired at any point in the window, even briefly
ever=$(prom_count "count(max_over_time(ALERTS{alertname!=\"Watchdog\"}[${dur}s])) or vector(0)")
p95=$(prom_count "histogram_quantile(0.95, sum by (le)(rate(http_request_duration_seconds_bucket{namespace=\"demo\",service=\"frontend\",route!~\"/health|/metrics\"}[${dur}s])))")
errs=$(prom_count "sum(increase(http_requests_total{namespace=\"demo\",status=~\"5..\"}[${dur}s])) or vector(0)")
ok=false; [ "$ever" = "0" ] && [ "$seen" = "0" ] && ok=true
jq -n --arg s "$start" --arg e "$end" --argjson d "$dur" --arg ever "$ever" --arg p95 "$p95" --arg errs "$errs" --argjson ok "$ok" \
  '{scenario:"control", start:$s, end:$e, seconds:$d, alerts_seen:($ever|tonumber), frontend_p95_seconds:($p95|tonumber), http_5xx:($errs|tonumber), pass:$ok}' | tee "$OUT"
[ "$ok" = true ]
