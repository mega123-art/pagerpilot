#!/usr/bin/env bash
# Restore the original frontend config: reset the repo to baseline, redeploy the frontend,
# drop the deployment record. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib.sh"
. "$HERE/../../scripts/shop.sh"

shop_reset
"$HERE/../../scripts/deploy.sh" frontend
$K -n demo rollout status deploy/frontend --timeout=120s
wait_quiet
