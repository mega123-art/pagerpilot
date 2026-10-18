#!/usr/bin/env bash
# smoke.sh <scenario>: inject, wait for the alert, capture the real webhook payload,
# revert, confirm the alert resolves and the system returns to baseline.
# Writes evals/fixtures/alerts/<id>.json (webhook body) and evals/fixtures/runs/<id>.json (timings).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../scenarios/lib.sh"
id=${1:?usage: smoke.sh <scenario>}
ROOT="$(cd "$HERE/../.." && pwd)"
SPEC="$ROOT/evals/scenarios/$id.yaml"
[ -f "$SPEC" ] || { echo "no $SPEC" >&2; exit 1; }
OUT_ALERT="$ROOT/evals/fixtures/alerts/$id.json"
OUT_RUN="$ROOT/evals/fixtures/runs/$id.json"
mkdir -p "$(dirname "$OUT_ALERT")" "$(dirname "$OUT_RUN")"

# primary alert: the first expected alert on the target service, else the first one
read -r alertname service settle < <(python3 - "$SPEC" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
al = [a for a in d["expected_alerts"] if a["service"] == d["target_service"]] or d["expected_alerts"]
print(al[0]["alertname"], al[0]["service"], d.get("settle_seconds", 300))
PY
)
timeout=$((settle + 600))
AM="/api/v1/namespaces/monitoring/services/pagerpilot-monitoring-kube-alertmanager:9093/proxy/api/v2/alerts"
iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

echo "== $id: expecting $alertname on $service (timeout ${timeout}s)"
# the previous run may still be inside the lookback window; give the baseline time to settle
ready=false
for _ in $(seq 1 60); do
  if SLO_WINDOW=2m "$HERE/verify.sh" >/dev/null 2>&1; then ready=true; break; fi
  sleep 10
done
[ "$ready" = true ] || { echo "baseline not healthy before inject; run make verify" >&2; "$HERE/verify.sh" >&2 || true; exit 1; }

reverted=0
cleanup() { [ "$reverted" = 1 ] || { echo "== aborting: reverting" >&2; "$HERE/../scenarios/$id/revert.sh" || true; }; }
trap cleanup EXIT

inject_at=$(iso); t0=$SECONDS
"$HERE/../scenarios/$id/inject.sh"
injected_at=$(iso)

echo "== waiting for $alertname/$service to fire"
firing_at=""
while [ $((SECONDS - t0)) -lt "$timeout" ]; do
  firing_at=$($K get --raw "$AM" | jq -r --arg a "$alertname" --arg s "$service" \
    '[.[] | select(.labels.alertname==$a and .labels.service==$s and .status.state=="active")][0].startsAt // empty')
  [ -n "$firing_at" ] && break
  sleep 10
done
[ -n "$firing_at" ] || { echo "alert never fired within ${timeout}s" >&2; exit 1; }
detect_s=$((SECONDS - t0))
echo "== firing since $firing_at (${detect_s}s after inject)"

# the webhook body alert-echo received is exactly what the agent will get
echo "== waiting for webhook delivery"
payload=""
for _ in $(seq 1 30); do
  payload=$($K -n platform logs deploy/alert-echo --since=2h 2>/dev/null | jq -c --arg a "$alertname" --arg s "$service" --arg t "$inject_at" \
    'select(.message=="alert webhook received") | select(.payload.status=="firing" and .payload.groupLabels.alertname==$a and .payload.groupLabels.service==$s and .time >= $t)' \
    | head -1)
  [ -n "$payload" ] && break
  sleep 5
done
[ -n "$payload" ] || { echo "no webhook payload received" >&2; exit 1; }
echo "$payload" | jq '.payload' > "$OUT_ALERT"
webhook_at=$(echo "$payload" | jq -r .time)

revert_t=$SECONDS; revert_at=$(iso)
"$HERE/../scenarios/$id/revert.sh"
reverted=1
revert_s=$((SECONDS - revert_t))

echo "== waiting for resolved notification"
resolved_at=""
for _ in $(seq 1 36); do
  resolved_at=$($K -n platform logs deploy/alert-echo --since=2h 2>/dev/null | jq -r --arg a "$alertname" --arg s "$service" --arg t "$revert_at" \
    'select(.message=="alert webhook received") | select(.payload.status=="resolved" and .payload.groupLabels.alertname==$a and .payload.groupLabels.service==$s and .time >= $t) | .payload.alerts[0].endsAt' \
    | head -1)
  [ -n "$resolved_at" ] && break
  sleep 5
done
[ -n "$resolved_at" ] || { echo "no resolved notification" >&2; exit 1; }

echo "== confirming baseline"
baseline=false
for _ in $(seq 1 30); do
  if SLO_WINDOW=2m "$HERE/verify.sh" >/dev/null 2>&1; then baseline=true; break; fi
  sleep 10
done

jq -n --arg id "$id" --arg alert "$alertname" --arg svc "$service" --arg inject "$inject_at" --arg injected "$injected_at" \
  --arg firing "$firing_at" --arg webhook "$webhook_at" --arg revert "$revert_at" --arg resolved "$resolved_at" \
  --argjson detect "$detect_s" --argjson revert_s "$revert_s" --argjson baseline "$baseline" \
  '{scenario:$id, alert:$alert, service:$svc, inject_started:$inject, inject_finished:$injected, alert_firing_at:$firing,
    webhook_received_at:$webhook, seconds_inject_to_firing:$detect, revert_started:$revert, revert_seconds:$revert_s,
    alert_resolved_at:$resolved, baseline_restored:$baseline}' > "$OUT_RUN"
cat "$OUT_RUN"
[ "$baseline" = true ] || { echo "baseline not restored" >&2; exit 1; }
echo "== $id: PASS"
