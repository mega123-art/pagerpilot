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
