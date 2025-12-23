# ============
# Variables
# ============
K8S_DIR        := deploy/k8s
K8S_NAMESPACE  ?= default
K8S_CONTEXT    ?= # opcional: kubectl context, déjalo vacío si sólo tienes uno
APP_NAME       := bravo-multipais
IMAGE          ?= tu-registry/bravo_multipais:0.1.0

KUBECTL        := kubectl
ifdef K8S_CONTEXT
KUBECTL        := kubectl --context $(K8S_CONTEXT)
endif

# ============
# Targets
# ============

.PHONY: k8s-apply
k8s-apply:
	@echo ">>> Aplicando manifiestos en namespace $(K8S_NAMESPACE)..."
	$(KUBECTL) apply -n $(K8S_NAMESPACE) -f $(K8S_DIR)

.PHONY: k8s-delete
k8s-delete:
	@echo ">>> Eliminando manifiestos en namespace $(K8S_NAMESPACE)..."
	$(KUBECTL) delete -n $(K8S_NAMESPACE) -f $(K8S_DIR) || true

# Rollout restart sólo del backend web
.PHONY: k8s-restart-web
k8s-restart-web:
	@echo ">>> Rollout restart de deployment web..."
	$(KUBECTL) rollout restart deployment/$(APP_NAME)-web -n $(K8S_NAMESPACE)

# Rollout restart sólo de workers
.PHONY: k8s-restart-workers
k8s-restart-workers:
	@echo ">>> Rollout restart de deployment workers..."
	$(KUBECTL) rollout restart deployment/$(APP_NAME)-workers -n $(K8S_NAMESPACE)

# Actualizar imagen de ambos deployments (útil tras docker push)
.PHONY: k8s-set-image
k8s-set-image:
	@echo ">>> Seteando imagen $(IMAGE) en deployments web y workers..."
	$(KUBECTL) set image deployment/$(APP_NAME)-web \
		$(APP_NAME)=${IMAGE} \
		-n $(K8S_NAMESPACE)
	$(KUBECTL) set image deployment/$(APP_NAME)-workers \
		$(APP_NAME)-workers=${IMAGE} \
		-n $(K8S_NAMESPACE)

# Logs rápidos
.PHONY: k8s-logs-web
k8s-logs-web:
	@echo ">>> Logs de un pod web..."
	$(KUBECTL) logs -n $(K8S_NAMESPACE) \
		$$( $(KUBECTL) get pods -n $(K8S_NAMESPACE) -l app=$(APP_NAME),component=web -o name | head -n1 ) \
		-f

.PHONY: k8s-logs-workers
k8s-logs-workers:
	@echo ">>> Logs de un pod worker..."
	$(KUBECTL) logs -n $(K8S_NAMESPACE) \
		$$( $(KUBECTL) get pods -n $(K8S_NAMESPACE) -l app=$(APP_NAME),component=worker -o name | head -n1 ) \
		-f