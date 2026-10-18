#!/usr/bin/env bash
# Heavy export calls hold pooled connections. Settle: ~1 min for pool waiters and alerts.
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
start_client "$(dirname "$0")/client.js"
