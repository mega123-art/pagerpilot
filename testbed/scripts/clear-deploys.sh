#!/usr/bin/env bash
# clear-deploys.sh: remove the deployment records created for an incident (idempotent).
# GitHub only deletes inactive deployments, so mark each inactive first.
set -euo pipefail
. "$(dirname "$0")/shop.sh"
for id in $(gh api "repos/$SHOP_REPO/deployments" --paginate -q '.[].id'); do
  gh api "repos/$SHOP_REPO/deployments/$id/statuses" -f state=inactive >/dev/null
  gh api -X DELETE "repos/$SHOP_REPO/deployments/$id" >/dev/null
done
