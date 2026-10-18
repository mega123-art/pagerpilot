# PagerPilot testbed. Every target that touches the cluster goes through `guard`.
# orders and frontend are built from the demo-shop repo (see scripts/shop.sh).
CONTEXT  := kind-pagerpilot
K        := kubectl --context $(CONTEXT)
SERVICES := orders frontend

.PHONY: guard build up down reset verify inject revert smoke settle monitoring loadgen

guard:
	@[ "$$(kubectl config current-context)" = "$(CONTEXT)" ] || \
	  { echo "refusing to run: kubectl context is '$$(kubectl config current-context)', need '$(CONTEXT)'" >&2; exit 1; }

# Build baseline images (<service>:<semver>) and load them into kind.
build: guard
	@set -e; for s in $(SERVICES) alert-echo; do scripts/build-image.sh $$s >/dev/null; done

up: guard
	$(K) apply -f k8s/namespace.yaml -f k8s/servicemonitor.yaml -f services/postgres/k8s/ -f monitoring/rules/ -f monitoring/dashboard.yaml
	@set -e; for s in $(SERVICES) alert-echo; do scripts/deploy.sh $$s; done
	@$(MAKE) --no-print-directory loadgen

# Scripts live in ConfigMap loadgen-scripts (every file in loadgen/); changing one restarts the pod.
loadgen: guard
	$(K) -n demo create configmap loadgen-scripts --from-file=loadgen --dry-run=client -o yaml \
	  | $(K) label --local -f - app.kubernetes.io/part-of=demo-shop -o yaml | $(K) apply -f -
	$(K) apply -f k8s/loadgen.yaml
	$(K) -n demo rollout restart deploy/loadgen

# Block until no alerts are pending/firing for ns demo.
settle: guard
	@. scenarios/lib.sh && wait_quiet

# Applies monitoring/prometheus-values.yaml (Alertmanager routing, disabled kind components).
monitoring: guard
	helm --kube-context $(CONTEXT) upgrade pagerpilot-monitoring prometheus-community/kube-prometheus-stack \
	  --version 92.10.1 -n monitoring -f monitoring/prometheus-values.yaml

# Deletes everything labelled part-of=demo-shop in ns demo (Deployments, Services,
# ConfigMaps; postgres data is an emptyDir so it goes too) plus the demo-shop
# ServiceMonitor, rules and dashboard. Keeps the monitoring stack, namespaces, alert-echo and images.
down: guard
	$(K) delete -n demo deploy,svc,configmap -l app.kubernetes.io/part-of=demo-shop
	$(K) delete -n monitoring servicemonitor/demo-shop prometheusrule/demo-shop configmap/demo-shop-dashboard --ignore-not-found

reset: down up

# Checks so far: pods Ready, postgres seeded, targets up. P7 extends (SLOs, alerts, logs).
verify: guard
	@$(K) -n demo wait --for=condition=Ready pod -l app.kubernetes.io/part-of=demo-shop --timeout=180s
	@n=$$($(K) -n demo exec deploy/postgres -- psql -U postgres -d shop -tAc 'select count(*) from orders'); \
	  [ "$$n" -ge 500000 ] && echo "orders seeded ($$n rows)" || { echo "orders table missing or unseeded ($$n); check: kubectl -n demo logs deploy/postgres, or make reset" >&2; exit 1; }
	@$(K) -n monitoring get --raw '/api/v1/namespaces/monitoring/services/pagerpilot-monitoring-kube-prometheus:9090/proxy/api/v1/query?query=up%7Bnamespace%3D%22demo%22%7D' \
	  | jq -e '(.data.result | length > 0) and all(.data.result[]; .value[1] == "1")' >/dev/null \
	  && echo "all demo targets up=1" || { echo "demo targets missing or down" >&2; exit 1; }

inject revert: guard
	@[ -n "$(S)" ] || { echo "usage: make $@ S=<scenario>" >&2; exit 1; }
	@[ -x scenarios/$(S)/$@.sh ] || { echo "no scenarios/$(S)/$@.sh" >&2; exit 1; }
	scenarios/$(S)/$@.sh

smoke: guard
	@echo "smoke lands in P7" >&2; exit 1
