#!/usr/bin/env bash
# Source from every script that touches the cluster.
EXPECTED_CONTEXT=kind-pagerpilot
actual=$(kubectl config current-context 2>/dev/null)
if [ "$actual" != "$EXPECTED_CONTEXT" ]; then
  echo "refusing to run: kubectl context is '$actual', need '$EXPECTED_CONTEXT'" >&2
  exit 1
fi
K="kubectl --context $EXPECTED_CONTEXT"
