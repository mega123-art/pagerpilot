#!/usr/bin/env bash
# build-image.sh <service> [git-ref]: build <service>:<version> and load it into kind.
# orders/frontend are built from the demo-shop repo at <git-ref> (default: baseline);
# alert-echo is built from this repo. A tag is never rebuilt with different code.
# stdout: "<version> <git-sha>"
set -euo pipefail
. "$(dirname "$0")/../scenarios/guard.sh"
. "$(dirname "$0")/shop.sh"
svc=$1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

if [ "$svc" = alert-echo ]; then
  cp -R "$TESTBED/services/alert-echo/." "$tmp/"
  rm -rf "$tmp/k8s" "$tmp/node_modules"
  sha=$(git -C "$TESTBED" rev-parse --short HEAD)
  paths="."; pkg="$tmp/package.json"
else
  ref=${2:-$(baseline_ref "$svc")}
  shop_sync
  git -C "$SHOP" archive "$ref" | tar -x -C "$tmp"
  sha=$(git -C "$SHOP" rev-parse --short "$ref^{commit}")
  paths="$svc _shared"; pkg="$tmp/$svc/package.json"
fi

version=$(node -p "require('$pkg').version")
hash=$(cd "$tmp" && find $paths -type f -not -path '*/node_modules/*' | sort | xargs shasum | shasum | cut -c1-12)
old=$(docker image inspect "$svc:$version" --format '{{index .Config.Labels "code.hash"}}' 2>/dev/null || true)
if [ -n "$old" ] && [ "$old" != "$hash" ]; then
  echo "$svc:$version exists with different code; bump the version (a tag must never map to different code)" >&2
  exit 1
fi
if [ "$old" != "$hash" ]; then
  docker build -q -f "$tmp/Dockerfile" --build-arg SERVICE="$svc" --build-arg VERSION="$version" \
    --build-arg GIT_SHA="$sha" --build-arg CODE_HASH="$hash" -t "$svc:$version" "$tmp" >&2
fi
kind load docker-image "$svc:$version" --name pagerpilot >&2
sha=$(docker image inspect "$svc:$version" --format '{{index .Config.Labels "git.sha"}}')
echo "$version $sha"
