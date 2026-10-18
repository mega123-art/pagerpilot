#!/usr/bin/env bash
# Roll orders back to 1.0.2, then remove the commits, tag and deployment record so later
# runs see a quiet repo. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib.sh"
. "$HERE/../../scripts/shop.sh"

"$HERE/../../scripts/deploy.sh" orders
$K -n demo rollout status deploy/orders --timeout=120s
shop_reset
wait_quiet
