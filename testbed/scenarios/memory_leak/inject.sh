#!/usr/bin/env bash
# Many visitors with unique session ids. Settle: first OOM kill of orders ~5 min after inject.
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
start_client "$(dirname "$0")/client.js"
