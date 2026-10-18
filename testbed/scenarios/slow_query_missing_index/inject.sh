#!/usr/bin/env bash
# Drops the customer_id index and adds order-history traffic. Settle: ~2 min.
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
$K -n demo exec deploy/postgres -- psql -U postgres -d shop -qc "DROP INDEX IF EXISTS idx_orders_customer_id"
start_client "$(dirname "$0")/client.js"
