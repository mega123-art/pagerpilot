# PagerPilot testbed. Every target that touches the cluster goes through `guard`.
CONTEXT  := kind-pagerpilot
K        := kubectl --context $(CONTEXT)
SERVICES := orders frontend alert-echo
SVC_DIR  := services
GIT_SHA  := $(shell git rev-parse --short HEAD)$(shell git diff --quiet HEAD -- . || echo -dirty)

.PHONY: monitoring loadgen guard build up down reset verify inject revert smoke

guard:
	@[ "$$(kubectl config current-context)" = "$(CONTEXT)" ] || \
	  { echo "refusing to run: kubectl context is '$$(kubectl config current-context)', need '$(CONTEXT)'" >&2; exit 1; }

# Build each service image tagged <service>:<semver> and load it into kind.
# A tag is never reused for different code: the image records a hash of the
# service dir + _shared, and the build fails if the tag exists with another hash.
build: guard
	@set -e; for s in $(SERVICES); do \
	  v=$$(node -p "require('./$(SVC_DIR)/$$s/package.json').version"); \
	  h=$$(find $(SVC_DIR)/$$s $(SVC_DIR)/_shared -type f -not -path '*/node_modules/*' -not -path '*/k8s/*' | sort | xargs shasum | shasum | cut -c1-12); \
	  old=$$(docker image inspect $$s:$$v --format '{{index .Config.Labels "code.hash"}}' 2>/dev/null || true); \
	  if [ -n "$$old" ] && [ "$$old" != "$$h" ]; then \
	    echo "$$s:$$v exists with different code; bump version in $(SVC_DIR)/$$s/package.json (a tag must never map to different code)" >&2; exit 1; fi; \
	  [ "$$old" = "$$h" ] || docker build -q -f $(SVC_DIR)/Dockerfile \
	    --build-arg SERVICE=$$s --build-arg VERSION=$$v --build-arg GIT_SHA=$(GIT_SHA) --build-arg CODE_HASH=$$h \
	    -t $$s:$$v $(SVC_DIR); \
	  kind load docker-image $$s:$$v --name pagerpilot; \
	done

up: build
	$(K) apply -f k8s/namespace.yaml -f k8s/servicemonitor.yaml -f $(SVC_DIR)/postgres/k8s/ -f monitoring/rules/ -f monitoring/dashboard.yaml
	@set -e; for s in $(SERVICES); do \
	  v=$$(node -p "require('./$(SVC_DIR)/$$s/package.json').version"); \
	  $(K) apply -f $(SVC_DIR)/$$s/k8s/service.yaml; \
	  sha=$$(docker image inspect $$s:$$v --format '{{index .Config.Labels "git.sha"}}'); \
	  VERSION=$$v GIT_SHA=$$sha envsubst '$$VERSION $$GIT_SHA' < $(SVC_DIR)/$$s/k8s/deployment.yaml | $(K) apply -f -; \
	done
	@$(MAKE) --no-print-directory loadgen

# Applies monitoring/prometheus-values.yaml (Alertmanager routing, disabled kind components).
monitoring: guard
	helm --kube-context $(CONTEXT) upgrade pagerpilot-monitoring prometheus-community/kube-prometheus-stack \
	  --version 92.10.1 -n monitoring -f monitoring/prometheus-values.yaml

# Scripts live in ConfigMap loadgen-scripts (every file in loadgen/); changing one restarts the pod.
loadgen: guard
	$(K) -n demo create configmap loadgen-scripts --from-file=loadgen --dry-run=client -o yaml \
	  | $(K) label --local -f - app.kubernetes.io/part-of=demo-shop -o yaml | $(K) apply -f -
	$(K) apply -f k8s/loadgen.yaml
	$(K) -n demo rollout restart deploy/loadgen

# Deletes everything labelled part-of=demo-shop in ns demo (Deployments, Services,
# the postgres ConfigMap; postgres data is an emptyDir so it goes too) plus the
# demo-shop ServiceMonitor. Keeps monitoring stack, namespaces and Docker images.
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
