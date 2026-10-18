#!/usr/bin/env bash
# Ship orders v1.1.0: commit + tag in the demo-shop repo, deploy it, record the deployment.
# Settle: errors begin at rollout; alerts fire ~2 min later.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib.sh"
. "$HERE/../../scripts/shop.sh"

shop_sync
if ! git -C "$SHOP" rev-parse -q --verify refs/tags/orders-v1.1.0 >/dev/null; then
  git -C "$SHOP" apply "$HERE/regression.diff"
  git -C "$SHOP" add -A
  git -C "$SHOP" commit -q -m "perf(orders): paginate order history by placed_at" -m "Order history is sorted on the new placed_at column so the lookup can use
the (customer_id, placed_at) index from 003_orders_placed_at.sql instead of
walking the primary key backwards."
  (cd "$SHOP/orders" && npm pkg set version=1.1.0 >/dev/null)
  git -C "$SHOP" add -A
  git -C "$SHOP" commit -q -m "chore(release): orders v1.1.0"
  git -C "$SHOP" tag orders-v1.1.0
  git -C "$SHOP" push -q origin main orders-v1.1.0
fi

"$HERE/../../scripts/deploy.sh" orders orders-v1.1.0
$K -n demo rollout status deploy/orders --timeout=120s
"$HERE/../../scripts/record-deploy.sh" orders-v1.1.0 "orders v1.1.0"
