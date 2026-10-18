# Shared helpers for scenario scripts. Source after the guard.
. "$(dirname "${BASH_SOURCE[0]}")/guard.sh"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# start_client <k6 script> [VAR=value ...]: run an extra traffic source in ns demo.
start_client() {
  local script=$1; shift
  $K -n demo create configmap ext-client-script --from-file=script.js="$script" --dry-run=client -o yaml \
    | $K label --local -f - app.kubernetes.io/part-of=demo-shop -o yaml | $K apply -f - >/dev/null
  $K apply -f "$LIB_DIR/ext-client.yaml" >/dev/null
  local args=()
  for kv in "$@"; do args+=("$kv"); done
  [ ${#args[@]} -gt 0 ] && $K -n demo set env deploy/ext-client "${args[@]}" >/dev/null
  $K -n demo rollout restart deploy/ext-client >/dev/null
}

stop_client() {
  $K -n demo delete deploy/ext-client configmap/ext-client-script --ignore-not-found >/dev/null
}

# prom_count <promql>: first sample value of an instant query, 0 if empty.
prom_count() {
  $K -n monitoring get --raw "/api/v1/namespaces/monitoring/services/pagerpilot-monitoring-kube-prometheus:9090/proxy/api/v1/query?query=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$1")" \
    | jq -r '.data.result[0].value[1] // "0"'
}

# wait_quiet [timeout_s]: block until no alert (any state) exists for ns demo, so the
# next scenario starts from baseline. Prints how long that took.
wait_quiet() {
  local timeout=${1:-900} start=$SECONDS
  until [ "$(prom_count 'count(ALERTS{namespace="demo"}) or vector(0)')" = "0" ]; do
    [ $((SECONDS - start)) -lt "$timeout" ] || { echo "alerts still present after ${timeout}s" >&2; return 1; }
    sleep 10
  done
  echo "baseline after $((SECONDS - start))s"
}
