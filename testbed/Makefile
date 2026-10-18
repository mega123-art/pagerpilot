# PagerPilot testbed. Every target that touches the cluster goes through `guard`.
# orders and frontend are built from the demo-shop repo (see scripts/shop.sh).
CONTEXT  := kind-pagerpilot
K        := kubectl --context $(CONTEXT)
SERVICES := orders frontend

.PHONY: control guard build up down reset verify inject revert smoke settle monitoring loadgen

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

# Baseline checks: context, pods Ready, seed, targets up, SLOs, no stray alerts, Loki queryable.
verify: guard
	@scripts/verify.sh

inject revert: guard
	@[ -n "$(S)" ] || { echo "usage: make $@ S=<scenario>" >&2; exit 1; }
	@[ -x scenarios/$(S)/$@.sh ] || { echo "no scenarios/$(S)/$@.sh" >&2; exit 1; }
	scenarios/$(S)/$@.sh

# make smoke S=<id>: inject, wait for the alert, save the webhook payload to evals/fixtures/alerts/<id>.json,
# revert, confirm it resolves and the system returns to baseline.
smoke: guard
	@[ -n "$(S)" ] || { echo "usage: make smoke S=<scenario>" >&2; exit 1; }
	@scripts/smoke.sh $(S)

# 15 minutes with no change: there must be zero alerts.
control: guard
	@scripts/control.sh
