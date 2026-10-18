#!/usr/bin/env bash
# record-deploy.sh <git-ref> <description>: record a successful production deployment on GitHub.
set -euo pipefail
. "$(dirname "$0")/../scenarios/guard.sh"
. "$(dirname "$0")/shop.sh"
sha=$(git -C "$SHOP" rev-parse "$1^{commit}")
id=$(jq -n --arg ref "$sha" --arg d "$2" \
  '{ref:$ref, environment:"production", description:$d, auto_merge:false, required_contexts:[]}' \
  | gh api "repos/$SHOP_REPO/deployments" --input - -q .id)
gh api "repos/$SHOP_REPO/deployments/$id/statuses" -f state=success -f environment=production -f description="$2" >/dev/null
echo "deployment $id: $2"
