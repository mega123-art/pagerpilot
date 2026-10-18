# Helpers for the demo-shop source repo. Source after scenarios/guard.sh.
TESTBED="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHOP_REPO=mega123-art/pagerpilot-demo-shop
SHOP="$TESTBED/.cache/demo-shop"
BASE_REF=orders-v1.0.2   # tip of main in the baseline history

# baseline_ref <service>: the release each service runs when nothing is wrong
baseline_ref() {
  case "$1" in
    orders) echo orders-v1.0.2 ;;
    frontend) echo frontend-v1.0.0 ;;
    *) echo "unknown service $1" >&2; return 1 ;;
  esac
}

shop_sync() {
  [ -d "$SHOP/.git" ] || git clone -q "https://github.com/$SHOP_REPO.git" "$SHOP"
  git -C "$SHOP" fetch -q --tags --force --prune --prune-tags origin
  git -C "$SHOP" checkout -q -B main origin/main
}

# shop_reset: put the repo back on its baseline history and drop deployment records.
# Runs after a scenario so later runs see no recent commits or deployments.
shop_reset() {
  shop_sync
  git -C "$SHOP" push -q --force origin "$BASE_REF^{commit}:refs/heads/main"
  if git -C "$SHOP" ls-remote --tags origin orders-v1.1.0 | grep -q .; then
    git -C "$SHOP" push -q origin :refs/tags/orders-v1.1.0
  fi
  "$TESTBED/scripts/clear-deploys.sh"
  shop_sync
}
