.PHONY: build-dev build-prod build-dev-app build-prd-app deploy-dev-cluster destroy-dev-cluster cilium-cleanup install-prometheus-crds

KUSTOMIZE := kubectl kustomize

build-dev-app:
	@$(KUSTOMIZE) apps/development/$(APP) | envsubst

build-prd-app:
	@$(KUSTOMIZE) apps/production/$(APP) | envsubst

deploy-dev-cluster:
	@DNS_SERVER=$(DNS_SERVER) UEFI_PATH=$(UEFI_PATH) bash scripts/dev-cluster.sh

install-prometheus-crds:
	helm template prometheus-crds prometheus-community/prometheus-operator-crds | kubectl apply --server-side -f -

destroy-dev-cluster:
	bash scripts/teardown-cluster.sh

cilium-cleanup:
	kubectl get pods --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOSTNETWORK:.spec.hostNetwork --no-headers=true | grep '<none>' | awk '{print "-n "$1" "$2}' | xargs -L 1 -r kubectl delete pod

bootstrap:
	bash scripts/bootstrap.sh
