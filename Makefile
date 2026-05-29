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

## --- deploy (Docker container, ไม่ใช้ k8s) ---
.PHONY: deploy-staging
deploy-staging: docker-build ## Deploy staging as a Docker container (host port 3001)
	APP_IMAGE=$(IMAGE) APP_ENV=staging HOST_PORT=3001 \
	  docker compose -p cicd-jenkins-101-staging -f deploy/docker-compose.yml up -d
	@echo "staging:  http://localhost:3001/healthz"

.PHONY: deploy-production
deploy-production: ## Deploy production as a Docker container (host port 3002)
	APP_IMAGE=$(IMAGE) APP_ENV=production HOST_PORT=3002 \
	  docker compose -p cicd-jenkins-101-production -f deploy/docker-compose.yml up -d
	@echo "production:  http://localhost:3002/healthz"

.PHONY: undeploy
undeploy: ## Stop and remove staging + production containers
	-docker compose -p cicd-jenkins-101-staging -f deploy/docker-compose.yml down
	-docker compose -p cicd-jenkins-101-production -f deploy/docker-compose.yml down

.PHONY: demo
demo: deploy-staging ## One-shot: build + run staging container on :3001
