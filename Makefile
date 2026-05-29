CLUSTER ?= demo
# Local image tag (must be lowercase). The registry image name used in CI is
# derived in the Jenkinsfile.
IMAGE   ?= cicd-gitops-jenkins-101:dev

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

## --- jenkins (local) ---
.PHONY: jenkins-up
jenkins-up: ## Start local Jenkins (docker compose + JCasC) on :8088
	cd jenkins && docker compose up -d --build
	@echo "Jenkins UI: http://localhost:8088   (admin / admin)"

.PHONY: jenkins-down
jenkins-down: ## Stop and remove local Jenkins
	cd jenkins && docker compose down

.PHONY: jenkins-logs
jenkins-logs: ## Tail the Jenkins controller logs
	cd jenkins && docker compose logs -f jenkins

## --- app ---
.PHONY: install
install: ## Install app dependencies (generates package-lock.json)
	cd app && npm install

.PHONY: lint
lint: ## Lint the app
	cd app && npm run lint

.PHONY: test
test: ## Run unit tests with coverage
	cd app && npm run test:ci

.PHONY: run
run: ## Run the app locally on :3000
	cd app && npm start

.PHONY: docker-build
docker-build: ## Build the container image
	docker build -t $(IMAGE) app

## --- k6 ---
.PHONY: k6-smoke
k6-smoke: ## k6 smoke test (BASE_URL=...)
	k6 run tests/k6/smoke.js

.PHONY: k6-load
k6-load: ## k6 load test / perf gate
	k6 run tests/k6/load.js

.PHONY: k6-stress
k6-stress: ## k6 stress test
	k6 run tests/k6/stress.js

## --- kubernetes / gitops ---
.PHONY: cluster
cluster: ## Create a local kind cluster
	kind create cluster --name $(CLUSTER)

.PHONY: load-image
load-image: docker-build ## Load the local image into kind
	kind load docker-image $(IMAGE) --name $(CLUSTER)

.PHONY: argocd
argocd: ## Install ArgoCD into the cluster
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

.PHONY: deploy
deploy: ## Register the ArgoCD Applications (staging + production)
	kubectl apply -f argocd/staging.yaml
	kubectl apply -f argocd/production.yaml

.PHONY: argocd-password
argocd-password: ## Print the initial ArgoCD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

.PHONY: argocd-ui
argocd-ui: ## Port-forward the ArgoCD UI to https://localhost:8080
	kubectl -n argocd port-forward svc/argocd-server 8080:443

.PHONY: demo
demo: cluster argocd deploy ## One-shot: kind cluster + ArgoCD + Applications
	@echo "Open the UI:  make argocd-ui   (admin password: make argocd-password)"

.PHONY: clean
clean: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)
