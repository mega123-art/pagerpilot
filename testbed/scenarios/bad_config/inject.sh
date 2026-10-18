#!/usr/bin/env bash
# Commit a config change to the demo-shop repo and roll the frontend onto it.
# Settle: frontend errors begin at rollout; alerts fire ~2 min later.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib.sh"
. "$HERE/../../scripts/shop.sh"

shop_sync
cfg="$SHOP/deploy/frontend-config.yaml"
if ! grep -q 'orders:3002' "$cfg"; then
  sed -i.bak 's#http://orders:3001#http://orders:3002#' "$cfg" && rm -f "$cfg.bak"
  git -C "$SHOP" add deploy/frontend-config.yaml
  git -C "$SHOP" commit -q -m "chore(frontend): send orders traffic to the new listener on :3002" -m "Follow-up to the orders listener split; frontend should use the new port."
  git -C "$SHOP" push -q origin main
fi

"$HERE/../../scripts/deploy.sh" frontend
$K -n demo rollout status deploy/frontend --timeout=120s
"$HERE/../../scripts/record-deploy.sh" main "frontend config $(git -C "$SHOP" rev-parse --short HEAD)"
