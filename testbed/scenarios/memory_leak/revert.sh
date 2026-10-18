#!/usr/bin/env bash
# Stop the extra traffic and restart orders to drop the accumulated session map.
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
stop_client
$K -n demo rollout restart deploy/orders >/dev/null
$K -n demo rollout status deploy/orders --timeout=120s >/dev/null
