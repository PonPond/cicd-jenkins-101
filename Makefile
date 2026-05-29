CLUSTER ?= demo
# Local image tag (must be lowercase). The registry image name used in CI is
# derived in the Jenkinsfile.
IMAGE   ?= cicd-jenkins-101:dev

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

## --- kubernetes (push deploy) ---
.PHONY: cluster
cluster: ## Create a local kind cluster
	kind create cluster --name $(CLUSTER)

.PHONY: load-image
load-image: docker-build ## Load the local image into kind (offline use)
	kind load docker-image $(IMAGE) --name $(CLUSTER)

.PHONY: deploy-staging
deploy-staging: ## Deploy the staging overlay with kubectl
	kubectl create namespace demo-staging --dry-run=client -o yaml | kubectl apply -f -
	kustomize build k8s/overlays/staging | kubectl apply -f -
	kubectl -n demo-staging rollout status deploy/cicd-jenkins-101-staging --timeout=180s

.PHONY: deploy-production
deploy-production: ## Deploy the production overlay with kubectl
	kubectl create namespace demo-production --dry-run=client -o yaml | kubectl apply -f -
	kustomize build k8s/overlays/production | kubectl apply -f -
	kubectl -n demo-production rollout status deploy/cicd-jenkins-101-production --timeout=180s

.PHONY: demo
demo: cluster deploy-staging ## One-shot: kind cluster + deploy staging (pulls image from GHCR)
	@echo "Staging deployed to namespace demo-staging"

.PHONY: clean
clean: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)
