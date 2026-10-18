#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
stop_client
$K -n demo exec deploy/postgres -- psql -U postgres -d shop -qc "CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders (customer_id)"
wait_quiet
