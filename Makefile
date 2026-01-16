# ============
# Variables
# ============
K8S_DIR        ?= infra/k8s/base
K8S_NAMESPACE  ?= default
K8S_CONTEXT    ?=
K8S_VALIDATE   ?= true

APP_NAME       ?= bravo-multipais
IMAGE          ?= tu-registry/bravo_multipais:0.1.0

KUBECTL        := kubectl
ifneq ($(strip $(K8S_CONTEXT)),)
KUBECTL        := kubectl --context $(K8S_CONTEXT)
endif

KUBECTL_VALIDATE_FLAG :=
ifeq ($(strip $(K8S_VALIDATE)),false)
KUBECTL_VALIDATE_FLAG := --validate=false
endif

# ============
# Helpers
# ============

.PHONY: k8s-contexts
k8s-contexts:
	@echo ">>> Contextos disponibles:"
	@kubectl config get-contexts || true
	@echo ">>> Contexto actual:"
	@kubectl config current-context || true

.PHONY: k8s-preflight
k8s-preflight:
	@echo ">>> Checking kubectl context/cluster..."
	@kubectl config current-context >/dev/null 2>&1 || ( \
		echo "ERROR: No current kubectl context set."; \
		echo "Tip: run 'make k8s-contexts' and set K8S_CONTEXT=<name> or configure kubeconfig."; \
		echo "If you only want to inspect manifests offline: run 'make k8s-render'."; \
		exit 1 )
	@$(KUBECTL) cluster-info >/dev/null 2>&1 || ( \
		echo "ERROR: Cannot reach Kubernetes cluster with current context."; \
		echo "If you only want to inspect manifests offline: run 'make k8s-render'."; \
		exit 1 )

# No cluster needed
.PHONY: k8s-render
k8s-render:
	@echo ">>> Render YAML from $(K8S_DIR) (no cluster needed)"
	@cat $(K8S_DIR)/*.yaml

# ============
# Targets
# ============

.PHONY: k8s-apply
k8s-apply: k8s-preflight
	@echo ">>> Aplicando manifiestos en namespace $(K8S_NAMESPACE) desde $(K8S_DIR)..."
	$(KUBECTL) apply $(KUBECTL_VALIDATE_FLAG) -n $(K8S_NAMESPACE) -f $(K8S_DIR)

.PHONY: k8s-delete
k8s-delete: k8s-preflight
	@echo ">>> Eliminando manifiestos en namespace $(K8S_NAMESPACE) desde $(K8S_DIR)..."
	$(KUBECTL) delete $(KUBECTL_VALIDATE_FLAG) -n $(K8S_NAMESPACE) -f $(K8S_DIR) || true

.PHONY: k8s-restart-web
k8s-restart-web: k8s-preflight
	@echo ">>> Rollout restart de deployment web..."
	$(KUBECTL) rollout restart deployment/$(APP_NAME)-web -n $(K8S_NAMESPACE)

.PHONY: k8s-restart-workers
k8s-restart-workers: k8s-preflight
	@echo ">>> Rollout restart de deployment workers..."
	$(KUBECTL) rollout restart deployment/$(APP_NAME)-workers -n $(K8S_NAMESPACE)

.PHONY: k8s-set-image
k8s-set-image: k8s-preflight
	@echo ">>> Seteando imagen $(IMAGE) en deployments web y workers..."
	$(KUBECTL) set image deployment/$(APP_NAME)-web \
		$(APP_NAME)=$(IMAGE) \
		-n $(K8S_NAMESPACE)
	$(KUBECTL) set image deployment/$(APP_NAME)-workers \
		$(APP_NAME)-workers=$(IMAGE) \
		-n $(K8S_NAMESPACE)

.PHONY: k8s-logs-web
k8s-logs-web: k8s-preflight
	@echo ">>> Logs de un pod web..."
	$(KUBECTL) logs -n $(K8S_NAMESPACE) \
		$$( $(KUBECTL) get pods -n $(K8S_NAMESPACE) -l app=$(APP_NAME),component=web -o name | head -n1 ) \
		-f

.PHONY: k8s-logs-workers
k8s-logs-workers: k8s-preflight
	@echo ">>> Logs de un pod worker..."
	$(KUBECTL) logs -n $(K8S_NAMESPACE) \
		$$( $(KUBECTL) get pods -n $(K8S_NAMESPACE) -l app=$(APP_NAME),component=worker -o name | head -n1 ) \
		-f

.PHONY: compose-up
compose-up:
	@docker compose up --build

.PHONY: compose-down
compose-down:
	@docker compose down -v

.PHONY: smoke
smoke:
	@echo ">>> Waiting for web to be healthy..."
	@curl -fsS http://localhost:4000/healthz >/dev/null
	@echo ">>> OK healthz"