#!/usr/bin/env bash
# deploy.sh <service> [git-ref]: build the release and apply its Deployment.
# frontend also applies deploy/frontend-config.yaml from the repo's main branch.
set -euo pipefail
. "$(dirname "$0")/../scenarios/guard.sh"
. "$(dirname "$0")/shop.sh"
svc=$1
read -r version sha < <("$TESTBED/scripts/build-image.sh" "$@")
config_sha=""
if [ "$svc" = frontend ]; then
  git -C "$SHOP" show origin/main:deploy/frontend-config.yaml | $K apply -f - >&2
  config_sha=$(git -C "$SHOP" log -1 --format=%h origin/main -- deploy/frontend-config.yaml)
fi
$K apply -f "$TESTBED/services/$svc/k8s/service.yaml" >&2
VERSION=$version GIT_SHA=$sha CONFIG_SHA=$config_sha \
  envsubst '$VERSION $GIT_SHA $CONFIG_SHA' < "$TESTBED/services/$svc/k8s/deployment.yaml" | $K apply -f - >&2
echo "$svc $version $sha"
