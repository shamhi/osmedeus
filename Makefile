.PHONY: build run test test-unit test-integration test-workflow-integration test-e2e test-e2e-verbose test-e2e-ssh test-e2e-api test-e2e-nix test-e2e-install test-e2e-cloud test-sudo test-cloud test-docker test-ssh test-distributed distributed-e2e-up distributed-e2e-run distributed-e2e-down test-canary-all test-canary-repo test-canary-domain test-canary-ip test-canary-general canary-up canary-down test-all test-summary test-ci clean install install-gotestsum lint fmt db-seed db-clean db-migrate run-server-debug swagger update-ui snapshot-release github-release run-github-action docker-toolbox docker-toolbox-run docker-toolbox-shell docker-publish ai-build ai-up ai-down ai-rebuild ai-restart ai-logs ai-shell ai-scan ai-recon ai-vuln ai-redteam ai-status ai-tools ai-clean ai-validate

# Go parameters
GOCMD=go
GOBUILD=$(GOCMD) build
GOTEST=$(GOCMD) test
GOGET=$(GOCMD) get
GOFMT=$(GOCMD) fmt
GOMOD=$(GOCMD) mod
BINARY_NAME=osmedeus
BINARY_DIR=build/bin

# Console output prefix (cyan color)
PREFIX=\033[36m[*]\033[0m

# Gotestsum configuration - check GOPATH/bin first, then use go test fallback
GOPATH_BIN=$(shell go env GOPATH)/bin
GOTESTSUM_PATH=$(shell command -v gotestsum 2>/dev/null || echo $(GOPATH_BIN)/gotestsum)
GOTESTSUM_EXISTS=$(shell test -x $(GOTESTSUM_PATH) && echo yes || echo no)

# GOBIN for install target (falls back to GOPATH/bin if GOBIN is not set)
GOBIN_PATH=$(shell go env GOBIN)
ifeq ($(GOBIN_PATH),)
    GOBIN_PATH=$(GOPATH_BIN)
endif

ifeq ($(GOTESTSUM_EXISTS),yes)
    TESTCMD=@$(GOTESTSUM_PATH)
    TESTFLAGS=--format testdox --format-hide-empty-pkg --hide-summary=skipped,output --
    CANARY_TESTFLAGS=--format standard-verbose -- -v
else
    TESTCMD=$(GOTEST)
    TESTFLAGS=-v
    CANARY_TESTFLAGS=-v
endif

# Build flags
VERSION=$(shell cat internal/core/constants.go | grep 'VERSION =' | cut -d '"' -f 2)
AUTHOR=$(shell cat internal/core/constants.go | grep 'AUTHOR =' | cut -d '"' -f 2)
BUILD_TIME=$(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
COMMIT_HASH=$(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
LDFLAGS=-ldflags "-X main.BuildTime=$(BUILD_TIME) -X main.CommitHash=$(COMMIT_HASH)"

# Default target — show help
all: help

# Build the application and install to GOBIN
build:
	@echo "$(PREFIX) Building $(BINARY_NAME)..."
	@mkdir -p $(BINARY_DIR)
	$(GOBUILD) $(LDFLAGS) -o $(BINARY_DIR)/$(BINARY_NAME) ./cmd/osmedeus
	@echo "$(PREFIX) Installing $(BINARY_NAME) to $(GOBIN_PATH)..."
	@mkdir -p $(GOBIN_PATH)
	@rm -f $(GOBIN_PATH)/$(BINARY_NAME)
	@cp $(BINARY_DIR)/$(BINARY_NAME) $(GOBIN_PATH)/$(BINARY_NAME)

# Install to GOBIN (or GOPATH/bin) - requires prior build
install:
	@echo "$(PREFIX) Installing $(BINARY_NAME) to $(GOBIN_PATH)..."
	@if [ ! -f "$(BINARY_DIR)/$(BINARY_NAME)" ]; then \
		echo "$(PREFIX) Binary not found, building first..."; \
		$(MAKE) build; \
	else \
		mkdir -p $(GOBIN_PATH) && rm -f $(GOBIN_PATH)/$(BINARY_NAME) && cp $(BINARY_DIR)/$(BINARY_NAME) $(GOBIN_PATH)/$(BINARY_NAME); \
	fi

# Build for multiple platforms
build-all: build-linux build-darwin build-windows

build-linux:
	@echo "$(PREFIX) Building for Linux..."
	GOOS=linux GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o $(BINARY_DIR)/$(BINARY_NAME)-linux-amd64 ./cmd/osmedeus

build-darwin:
	@echo "$(PREFIX) Building for macOS..."
	GOOS=darwin GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o $(BINARY_DIR)/$(BINARY_NAME)-darwin-amd64 ./cmd/osmedeus
	GOOS=darwin GOARCH=arm64 $(GOBUILD) $(LDFLAGS) -o $(BINARY_DIR)/$(BINARY_NAME)-darwin-arm64 ./cmd/osmedeus

build-windows:
	@echo "$(PREFIX) Building for Windows..."
	GOOS=windows GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o $(BINARY_DIR)/$(BINARY_NAME)-windows-amd64.exe ./cmd/osmedeus

# Run the application
run:
	$(GOBUILD) $(LDFLAGS) -o $(BINARY_DIR)/$(BINARY_NAME) ./cmd/osmedeus
	./$(BINARY_DIR)/$(BINARY_NAME)

# Run with specific command
run-server: build
	@echo "$(PREFIX) Starting server..."
	./$(BINARY_DIR)/$(BINARY_NAME) serve

# Run server in debug mode without authentication
run-server-debug: build
	@echo "$(PREFIX) Starting debug server (no auth)..."
	./$(BINARY_DIR)/$(BINARY_NAME) serve -A --debug

# Install gotestsum (idempotent - silent if already installed)
install-gotestsum:
	@if [ ! -x "$(GOPATH_BIN)/gotestsum" ]; then \
		echo "Installing gotestsum..."; \
		go install gotest.tools/gotestsum@latest; \
	fi

# Run tests (install gotestsum first)
test: install-gotestsum
	$(TESTCMD) $(TESTFLAGS) -race ./...

# Run tests with coverage
test-coverage: install-gotestsum
	$(TESTCMD) $(TESTFLAGS) -race -coverprofile=coverage.out ./...
	$(GOCMD) tool cover -html=coverage.out -o coverage.html

# Unit tests (fast, no external dependencies)
test-unit: install-gotestsum
	$(TESTCMD) $(TESTFLAGS) -short ./...

# Integration tests (requires Docker for some tests)
test-integration: install-gotestsum
	$(TESTCMD) $(TESTFLAGS) -run Integration ./...

# Workflow integration tests (test/integration/)
test-workflow-integration: install-gotestsum
	$(TESTCMD) $(TESTFLAGS) ./test/integration/...

# E2E CLI tests (requires binary to be built first)
test-e2e: build install-gotestsum
	$(TESTCMD) $(TESTFLAGS) ./test/e2e/...

# E2E CLI tests with verbose output (for debugging)
test-e2e-verbose: build install-gotestsum
	@$(GOPATH_BIN)/gotestsum --format standard-verbose -- -v ./test/e2e/...

# Docker runner tests
test-docker: install-gotestsum
	docker compose -f docker-compose.test.yaml up -d
	$(TESTCMD) $(TESTFLAGS) -run Docker ./internal/runner/...
	docker compose -f docker-compose.test.yaml down

# SSH runner tests (using linuxserver/openssh-server)
test-ssh: install-gotestsum
	docker compose -f build/docker/docker-compose.test.yaml up -d ssh-server
	sleep 5
	$(TESTCMD) $(TESTFLAGS) -run SSH ./internal/runner/...
	docker compose -f build/docker/docker-compose.test.yaml down

# SSH E2E tests (full workflow tests with SSH runner)
test-e2e-ssh: build install-gotestsum
	@echo "$(PREFIX) Starting SSH server for E2E tests..."
	docker compose -f build/docker/docker-compose.test.yaml up -d ssh-server
	@echo "$(PREFIX) Waiting for SSH server to be ready..."
	@sleep 5
	@echo "$(PREFIX) Running SSH E2E tests..."
	$(TESTCMD) $(TESTFLAGS) -run SSH ./test/e2e/...
	@echo "$(PREFIX) Cleaning up..."
	docker compose -f build/docker/docker-compose.test.yaml down -v

# Distributed scan e2e tests (requires Docker for Redis)
test-distributed: build install-gotestsum
	@echo "$(PREFIX) Starting Redis for distributed tests..."
	docker compose -f build/docker/docker-compose.distributed-test.yaml up -d
	@echo "$(PREFIX) Waiting for Redis to be ready..."
	@sleep 3
	@echo "$(PREFIX) Running distributed tests..."
	$(TESTCMD) $(TESTFLAGS) -run Distributed ./test/e2e/...
	@echo "$(PREFIX) Cleaning up..."
	docker compose -f build/docker/docker-compose.distributed-test.yaml down -v

# Distributed E2E stack: redis + master + worker in Docker, then submit a real scan
distributed-e2e-up:
	@echo "$(PREFIX) Building distributed E2E stack..."
	docker compose -f build/docker/docker-compose.distributed-e2e.yaml build
	@echo "$(PREFIX) Starting distributed E2E stack (redis + master + worker)..."
	docker compose -f build/docker/docker-compose.distributed-e2e.yaml up -d
	@echo "$(PREFIX) Waiting for master to be healthy..."
	@for i in $$(seq 1 30); do \
		curl -sf http://localhost:8002/health > /dev/null 2>&1 && break; \
		sleep 2; \
	done
	@echo "$(PREFIX) Stack is ready. Master: http://localhost:8002"

distributed-e2e-run:
	@echo "$(PREFIX) Submitting distributed scan from master container..."
	docker exec osm-e2e-master osmedeus run -f repo -D -t https://github.com/juice-shop/juice-shop
	@echo "$(PREFIX) Scan submitted. Tailing worker logs (Ctrl+C to stop)..."
	docker compose -f build/docker/docker-compose.distributed-e2e.yaml logs -f worker

distributed-e2e-down:
	@echo "$(PREFIX) Stopping distributed E2E stack..."
	docker compose -f build/docker/docker-compose.distributed-e2e.yaml down -v

# API E2E tests (requires Docker for Redis, builds binary first)
test-e2e-api: build install-gotestsum
	@echo "$(PREFIX) Starting Redis for API tests..."
	docker compose -f build/docker/docker-compose.distributed-test.yaml up -d
	@echo "$(PREFIX) Waiting for Redis to be ready..."
	@sleep 3
	@echo "$(PREFIX) Running API E2E tests..."
	$(TESTCMD) $(TESTFLAGS) -run API ./test/e2e/...
	@echo "$(PREFIX) Cleaning up..."
	docker compose -f build/docker/docker-compose.distributed-test.yaml down -v

# Nix E2E tests (requires Docker for Nix container)
test-e2e-nix: build install-gotestsum
	@echo "$(PREFIX) Building Nix test container..."
	docker compose -f build/docker/docker-compose.nix-test.yaml build
	@echo "$(PREFIX) Starting Nix test container..."
	docker compose -f build/docker/docker-compose.nix-test.yaml up -d
	@echo "$(PREFIX) Waiting for Nix container to be ready..."
	@sleep 3
	@echo "$(PREFIX) Running Nix E2E tests..."
	$(TESTCMD) $(TESTFLAGS) -run TestNix ./test/e2e/...
	@echo "$(PREFIX) Cleaning up..."
	docker compose -f build/docker/docker-compose.nix-test.yaml down -v

# Install E2E tests (workflow and base installation from zip/URL/git)
test-e2e-install: build install-gotestsum
	@echo "$(PREFIX) Running install E2E tests..."
	$(TESTCMD) $(TESTFLAGS) -run TestInstall ./test/e2e/...

# Cloud E2E tests (cloud CLI commands and workflow)
test-e2e-cloud: build install-gotestsum
	@echo "$(PREFIX) Running cloud E2E tests..."
	$(TESTCMD) $(TESTFLAGS) -run TestCloud ./test/e2e/...

# Sudo-aware tests (requires interactive sudo prompt)
test-sudo: export OSM_TEST_SUDO=1
test-sudo: build install-gotestsum
	@echo "$(PREFIX) Running sudo-aware tests (may prompt for password)..."
	$(TESTCMD) $(TESTFLAGS) -run TestSudo ./test/e2e/...

# Cloud integration tests (internal cloud package tests)
test-cloud: install-gotestsum
	@echo "$(PREFIX) Running cloud integration tests..."
	$(TESTCMD) $(TESTFLAGS) ./test/integration/cloud_integration_test.go

# ── Canary tests (real scans inside Docker toolbox, requires Docker) ──────────

# Build and start the canary container (shared setup for individual targets)
canary-up: install-gotestsum
	@echo "$(PREFIX) Cleaning up any existing canary container..."
	-docker compose -f build/docker/docker-compose.canary.yaml down -v 2>/dev/null
	@echo "$(PREFIX) Building canary Docker image..."
	docker compose -f build/docker/docker-compose.canary.yaml build
	@echo "$(PREFIX) Starting canary container..."
	docker compose -f build/docker/docker-compose.canary.yaml up -d
	@echo "$(PREFIX) Waiting for API server..."
	@for i in $$(seq 1 60); do curl -sf http://localhost:8002/health > /dev/null 2>&1 && break || sleep 2; done
	@echo "$(PREFIX) Canary container ready."

# Tear down the canary container
canary-down:
	@echo "$(PREFIX) Cleaning up canary container..."
	docker compose -f build/docker/docker-compose.canary.yaml down -v

# Run ALL canary scans (builds container, runs all 4, cleans up — 60-120min)
test-canary-all: canary-up
	@echo "$(PREFIX) Running all canary tests (60-120 minutes)..."
	$(TESTCMD) $(CANARY_TESTFLAGS) -run TestCanary_FullSuite -timeout 120m ./test/e2e/... || ($(MAKE) canary-down && exit 1)
	@$(MAKE) canary-down

# Repo scan canary (juice-shop SAST, ~25min)
test-canary-repo: canary-up
	@echo "$(PREFIX) Running repo scan canary test..."
	$(TESTCMD) $(CANARY_TESTFLAGS) -run TestCanary_Repo -timeout 30m ./test/e2e/... || ($(MAKE) canary-down && exit 1)
	@$(MAKE) canary-down

# Domain-lite scan canary (hackerone.com, ~20min)
test-canary-domain: canary-up
	@echo "$(PREFIX) Running domain-lite scan canary test..."
	$(TESTCMD) $(CANARY_TESTFLAGS) -run TestCanary_Domain -timeout 25m ./test/e2e/... || ($(MAKE) canary-down && exit 1)
	@$(MAKE) canary-down

# CIDR scan canary (IP list, ~25min)
test-canary-ip: canary-up
	@echo "$(PREFIX) Running CIDR scan canary test..."
	$(TESTCMD) $(CANARY_TESTFLAGS) -run TestCanary_CIDR -timeout 30m ./test/e2e/... || ($(MAKE) canary-down && exit 1)
	@$(MAKE) canary-down

# Domain-list-recon scan canary (hackerone.com subdomains, ~40min)
test-canary-general: canary-up
	@echo "$(PREFIX) Running general scan canary test..."
	$(TESTCMD) $(CANARY_TESTFLAGS) -run TestCanary_General -timeout 45m ./test/e2e/... || ($(MAKE) canary-down && exit 1)
	@$(MAKE) canary-down

# All tests
test-all: test-unit test-integration

# Quick test summary (pass/fail only)
test-summary: install-gotestsum
	@$(GOPATH_BIN)/gotestsum --format dots-v2 -- -v ./...

# Test with JUnit XML output (for CI)
test-ci: install-gotestsum
	@$(GOPATH_BIN)/gotestsum --junitfile test-results.xml --format testdox --format-hide-empty-pkg --hide-summary=skipped,output -- -v -race ./...

# Clean build artifacts
clean:
	@echo "$(PREFIX) Cleaning..."
	rm -rf $(BINARY_DIR)
	rm -f coverage.out coverage.html test-results.xml

# Format code
fmt:
	$(GOFMT) ./...

# Lint code
lint:
	golangci-lint run

# Tidy dependencies
tidy:
	$(GOMOD) tidy

# Download dependencies
deps:
	$(GOMOD) download

# Update dependencies
update-deps:
	$(GOGET) -u ./...
	$(GOMOD) tidy

# Generate code (if needed)
generate:
	$(GOCMD) generate ./...

# Generate swagger documentation
swagger:
	@echo "$(PREFIX) Generating swagger documentation..."
	swag init -g pkg/server/server.go -o docs/api-swagger/ --packageName apiswagger

# Update embedded UI from dashboard build
update-ui:
	@echo "$(PREFIX) Updating embedded UI..."
	rm -rf public/ui/*
	cp -R ../osmedeus-dashboard/build/* public/ui/
	@echo "$(PREFIX) UI updated successfully!"

# Development setup
dev-setup: install-gotestsum
	@echo "$(PREFIX) Setting up development environment..."
	$(GOMOD) download
	@echo "$(PREFIX) Done!"

# Docker build
docker-build:
	docker build -t osmedeus:$(VERSION) .

# Docker run
docker-run:
	docker run -p 8002:8002 osmedeus:$(VERSION)

# Docker toolbox build (with all tools pre-installed)
docker-toolbox:
	@echo "$(PREFIX) Building osmedeus-toolbox Docker image..."
	docker compose -f build/docker/docker-compose.toolbox.yaml build \
		--build-arg BUILD_TIME=$(BUILD_TIME) \
		--build-arg COMMIT_HASH=$(COMMIT_HASH)
	@echo "$(PREFIX) osmedeus-toolbox image built successfully!"
	@echo "$(PREFIX) Run with: docker compose -f build/docker/docker-compose.toolbox.yaml up -d"

# Docker toolbox run
docker-toolbox-run:
	@echo "$(PREFIX) Starting osmedeus-toolbox container..."
	docker compose -f build/docker/docker-compose.toolbox.yaml up -d
	@echo "$(PREFIX) Container started! Enter with: docker exec -it osmedeus-toolbox bash"

# Docker toolbox shell (interactive)
docker-toolbox-shell:
	docker exec -it osmedeus-toolbox bash

# Docker publish (build and push to Docker Hub)
docker-publish:
	@echo "$(PREFIX) Building Docker image j3ssie/osmedeus:latest..."
	docker build -t j3ssie/osmedeus:latest \
		-f build/docker/Dockerfile \
		--build-arg BUILD_TIME=$(BUILD_TIME) \
		--build-arg COMMIT_HASH=$(COMMIT_HASH) \
		.
	@echo "$(PREFIX) Pushing to Docker Hub..."
	docker push j3ssie/osmedeus:latest
	@echo "$(PREFIX) Published j3ssie/osmedeus:latest successfully!"

# Release commands (GoReleaser)
snapshot-release:
	@echo "$(PREFIX) Update registry-metadata-direct-fetch.json..."
	cp ../osmedeus-registry/registry-metadata-direct-fetch.json public/presets/registry-metadata-direct-fetch.json
	@echo "$(PREFIX) Building $(BINARY_NAME)..."
	@mkdir -p $(BINARY_DIR)
	$(GOBUILD) $(LDFLAGS) -o $(BINARY_DIR)/$(BINARY_NAME) ./cmd/osmedeus
	@echo "$(PREFIX) Installing $(BINARY_NAME) to $(GOBIN_PATH)..."
	@mkdir -p $(GOBIN_PATH)
	@rm -f $(GOBIN_PATH)/$(BINARY_NAME)
	@cp $(BINARY_DIR)/$(BINARY_NAME) $(GOBIN_PATH)/$(BINARY_NAME)
	@echo "$(PREFIX) Building snapshot release"
	export GORELEASER_CURRENT_TAG="$(VERSION)" && goreleaser release --clean --skip=announce,publish,validate
	@echo "$(PREFIX) Install script copied to dist/install.sh"
	cp ../osmedeus-registry/install.sh dist/install.sh
	@echo "$(PREFIX) Prepare registry-metadata-direct-fetch.json"

local-release:
	@echo "$(PREFIX) Building $(BINARY_NAME)..."
	@mkdir -p $(BINARY_DIR)
	$(GOBUILD) $(LDFLAGS) -o $(BINARY_DIR)/$(BINARY_NAME) ./cmd/osmedeus
	@mkdir -p $(GOBIN_PATH)
	@rm -f $(GOBIN_PATH)/$(BINARY_NAME)
	@cp $(BINARY_DIR)/$(BINARY_NAME) $(GOBIN_PATH)/$(BINARY_NAME)
	@echo "$(PREFIX) Building local snapshot for mac and linux arm only for testing..."
	export GORELEASER_CURRENT_TAG="$(VERSION)" && goreleaser release --config test/goreleaser-debug.yaml --clean --skip=announce,publish,validate

github-release:
	@echo "$(PREFIX) Building and publishing GitHub release..."
	export GORELEASER_CURRENT_TAG="$(VERSION)" && goreleaser release --clean

run-github-action:
	unset GH_TOKEN && gh workflow run manual-release.yaml && gh workflow run nightly-release.yaml

run-homebrew-action:
	unset GH_TOKEN && (cd ../homebrew-tap/ && gh workflow run 226998251)

# Database commands
db-seed: build
	@echo "$(PREFIX) Seeding database..."
	./$(BINARY_DIR)/$(BINARY_NAME) db seed

db-clean: build
	@echo "$(PREFIX) Cleaning database..."
	./$(BINARY_DIR)/$(BINARY_NAME) db clean --force

db-migrate: build
	@echo "$(PREFIX) Running database migrations..."
	./$(BINARY_DIR)/$(BINARY_NAME) db migrate

# ── AI Scanner ─────────────────────────────────────────────────────────────────
AI_COMPOSE=docker compose -f build/docker/docker-compose.ai.yaml
AI_CONTAINER=osmedeus-ai

# Build the AI scanner Docker image
ai-build:
	@echo "$(PREFIX) Building AI scanner image..."
	$(AI_COMPOSE) build \
		--build-arg BUILD_TIME=$(BUILD_TIME) \
		--build-arg COMMIT_HASH=$(COMMIT_HASH)

# Start AI scanner stack (server + redis)
ai-up:
	@echo "$(PREFIX) Starting AI scanner stack..."
	$(AI_COMPOSE) up -d
	@echo "$(PREFIX) Waiting for health check..."
	@for i in $$(seq 1 30); do curl -sf http://localhost:8002/health > /dev/null 2>&1 && break || sleep 2; done
	@echo "$(PREFIX) AI scanner ready at http://localhost:8002"
	@printf "    \033[32mUsername:\033[0m $${OSM_USERNAME:-admin}\n"
	@printf "    \033[32mPassword:\033[0m $${OSM_PASSWORD:-admin}\n"

# Stop AI scanner stack
ai-down:
	@echo "$(PREFIX) Stopping AI scanner stack..."
	$(AI_COMPOSE) down

# Rebuild from scratch (no cache)
ai-rebuild:
	@echo "$(PREFIX) Rebuilding AI scanner image (no cache)..."
	$(AI_COMPOSE) build --no-cache \
		--build-arg BUILD_TIME=$(BUILD_TIME) \
		--build-arg COMMIT_HASH=$(COMMIT_HASH)
	@$(MAKE) ai-up

# Restart the scanner container (fast, no rebuild)
ai-restart:
	$(AI_COMPOSE) restart osmedeus

# View logs (follow mode)
ai-logs:
	$(AI_COMPOSE) logs -f osmedeus

# Open shell inside the scanner container
ai-shell:
	docker exec -it $(AI_CONTAINER) bash

# Run a full AI scan against a target (usage: make ai-scan TARGET=example.com)
ai-scan:
	@if [ -z "$(TARGET)" ]; then echo "Usage: make ai-scan TARGET=example.com"; exit 1; fi
	@echo "$(PREFIX) Running AI scan against $(TARGET)..."
	docker exec $(AI_CONTAINER) osmedeus run -f ai-scan -t $(TARGET)

# Run AI recon-only scan (usage: make ai-recon TARGET=example.com)
ai-recon:
	@if [ -z "$(TARGET)" ]; then echo "Usage: make ai-recon TARGET=example.com"; exit 1; fi
	@echo "$(PREFIX) Running AI recon against $(TARGET)..."
	docker exec $(AI_CONTAINER) osmedeus run -f ai-recon -t $(TARGET)

# Run AI vuln assessment (usage: make ai-vuln TARGET=example.com)
ai-vuln:
	@if [ -z "$(TARGET)" ]; then echo "Usage: make ai-vuln TARGET=example.com"; exit 1; fi
	@echo "$(PREFIX) Running AI vuln assessment against $(TARGET)..."
	docker exec $(AI_CONTAINER) osmedeus run -f ai-vuln -t $(TARGET)

# Run AI red team scan (usage: make ai-redteam TARGET=example.com)
ai-redteam:
	@if [ -z "$(TARGET)" ]; then echo "Usage: make ai-redteam TARGET=example.com"; exit 1; fi
	@echo "$(PREFIX) Running AI red team scan against $(TARGET)..."
	docker exec $(AI_CONTAINER) osmedeus run -f ai-redteam -t $(TARGET)

# Show status of AI scanner stack
ai-status:
	@$(AI_COMPOSE) ps
	@echo ""
	@docker exec $(AI_CONTAINER) osmedeus workflow list 2>/dev/null || echo "Container not running"

# List installed tools inside AI scanner container
ai-tools:
	@docker exec $(AI_CONTAINER) sh -c '\
		echo "── Go tools ──" && \
		for t in subfinder httpx dnsx nuclei naabu amass ffuf; do \
			which $$t >/dev/null 2>&1 && echo "  ✓ $$t" || echo "  ✗ $$t (missing)"; \
		done && \
		echo "── System tools ──" && \
		for t in nmap masscan nikto sqlmap testssl.sh chromium python3; do \
			which $$t >/dev/null 2>&1 && echo "  ✓ $$t" || echo "  ✗ $$t (missing)"; \
		done'

# Clean AI scanner resources (volumes, images)
ai-clean:
	@echo "$(PREFIX) Cleaning AI scanner..."
	$(AI_COMPOSE) down -v --rmi local 2>/dev/null || true

# Validate AI workflow YAML files
ai-validate: build
	@echo "$(PREFIX) Validating AI workflows..."
	@for f in workflows/flows/ai-*.yaml; do \
		echo "  Validating $$f..."; \
		./$(BINARY_DIR)/$(BINARY_NAME) workflow validate $$(basename $$f .yaml) 2>&1 || true; \
	done

# Help
help:
	@printf "\n"
	@printf "\033[38;5;39m   ╔═══════════════════════════════════════════════════════════╗\033[0m\n"
	@printf "\033[38;5;39m   ║\033[0m  \033[1;97m⚡ Osmedeus $(VERSION)\033[0m — AI-Driven Security Orchestration     \033[38;5;39m║\033[0m\n"
	@printf "\033[38;5;39m   ║\033[0m     \033[38;5;245mCrafted with \033[31m❤\033[38;5;245m by $(AUTHOR)\033[0m                       \033[38;5;39m║\033[0m\n"
	@printf "\033[38;5;39m   ╚═══════════════════════════════════════════════════════════╝\033[0m\n"
	@printf "\n"
	@printf "  \033[1;33m⬡ BUILD & INSTALL\033[0m\n"
	@printf "    \033[36mbuild\033[0m              Build and install binary to \$$GOBIN\n"
	@printf "    \033[36mbuild-all\033[0m          Cross-platform builds (linux, darwin, windows)\n"
	@printf "    \033[36minstall\033[0m            Install binary (builds first if needed)\n"
	@printf "    \033[36mclean\033[0m              Remove build artifacts and coverage files\n"
	@printf "\n"
	@printf "  \033[1;33m⬡ RUN\033[0m\n"
	@printf "    \033[36mrun\033[0m                Build and run the application\n"
	@printf "    \033[36mrun-server\033[0m         Start web server + UI on :8002\n"
	@printf "    \033[36mrun-server-debug\033[0m   Start server in debug mode (no auth)\n"
	@printf "\n"
	@printf "  \033[1;33m⬡ TEST\033[0m\n"
	@printf "    \033[36mtest\033[0m               All tests with race detection\n"
	@printf "    \033[36mtest-unit\033[0m          Fast unit tests (no external deps)\n"
	@printf "    \033[36mtest-integration\033[0m   Integration tests\n"
	@printf "    \033[36mtest-e2e\033[0m           E2E CLI tests  \033[38;5;245m│\033[0m \033[36mtest-e2e-verbose\033[0m  Verbose E2E\n"
	@printf "    \033[36mtest-e2e-ssh\033[0m       SSH E2E tests  \033[38;5;245m│\033[0m \033[36mtest-e2e-api\033[0m      API E2E (Redis)\n"
	@printf "    \033[36mtest-e2e-nix\033[0m       Nix E2E tests  \033[38;5;245m│\033[0m \033[36mtest-e2e-install\033[0m  Install E2E\n"
	@printf "    \033[36mtest-e2e-cloud\033[0m     Cloud E2E      \033[38;5;245m│\033[0m \033[36mtest-sudo\033[0m         Sudo-aware E2E\n"
	@printf "    \033[36mtest-docker\033[0m        Docker runner   \033[38;5;245m│\033[0m \033[36mtest-ssh\033[0m          SSH runner\n"
	@printf "    \033[36mtest-distributed\033[0m   Distributed E2E \033[38;5;245m│\033[0m \033[36mtest-cloud\033[0m        Cloud integration\n"
	@printf "    \033[36mtest-coverage\033[0m      Coverage report \033[38;5;245m│\033[0m \033[36mtest-ci\033[0m           JUnit XML output\n"
	@printf "    \033[36mtest-summary\033[0m       Quick dots summary\n"
	@printf "    \033[38;5;245m── Canary (real scans in Docker) ──────────────────────\033[0m\n"
	@printf "    \033[36mtest-canary-all\033[0m    All canary scans       \033[38;5;245m│\033[0m \033[36mcanary-up\033[0m / \033[36mcanary-down\033[0m\n"
	@printf "    \033[36mtest-canary-repo\033[0m   SAST juice-shop        \033[38;5;245m│\033[0m \033[36mtest-canary-domain\033[0m  Domain recon\n"
	@printf "    \033[36mtest-canary-ip\033[0m     CIDR scan              \033[38;5;245m│\033[0m \033[36mtest-canary-general\033[0m General recon\n"
	@printf "    \033[38;5;245m── Distributed E2E stack ──────────────────────────────\033[0m\n"
	@printf "    \033[36mdistributed-e2e-up\033[0m   Start stack  \033[38;5;245m│\033[0m \033[36mdistributed-e2e-run\033[0m   Submit scan\n"
	@printf "    \033[36mdistributed-e2e-down\033[0m Tear down\n"
	@printf "\n"
	@printf "  \033[1;33m⬡ DEVELOPMENT\033[0m\n"
	@printf "    \033[36mdev-setup\033[0m          Bootstrap dev environment\n"
	@printf "    \033[36mfmt\033[0m                Format code       \033[38;5;245m│\033[0m \033[36mlint\033[0m     Run golangci-lint\n"
	@printf "    \033[36mtidy\033[0m               go mod tidy       \033[38;5;245m│\033[0m \033[36mdeps\033[0m     Download dependencies\n"
	@printf "    \033[36mupdate-deps\033[0m        Update all deps   \033[38;5;245m│\033[0m \033[36mgenerate\033[0m Run go generate\n"
	@printf "    \033[36mswagger\033[0m            Generate API docs \033[38;5;245m│\033[0m \033[36mupdate-ui\033[0m Sync dashboard build\n"
	@printf "\n"
	@printf "  \033[1;33m⬡ DOCKER\033[0m\n"
	@printf "    \033[36mdocker-build\033[0m       Build image        \033[38;5;245m│\033[0m \033[36mdocker-run\033[0m      Run container\n"
	@printf "    \033[36mdocker-publish\033[0m     Push to Docker Hub\n"
	@printf "    \033[36mdocker-toolbox\033[0m     Build toolbox image (all tools pre-installed)\n"
	@printf "    \033[36mdocker-toolbox-run\033[0m Start toolbox     \033[38;5;245m│\033[0m \033[36mdocker-toolbox-shell\033[0m Enter shell\n"
	@printf "\n"
	@printf "  \033[1;35m⬡ AI SCANNER\033[0m \033[38;5;245m(LLM-driven autonomous security scanning)\033[0m\n"
	@printf "    \033[38;5;245m── Lifecycle ──────────────────────────────────────────\033[0m\n"
	@printf "    \033[35mai-build\033[0m           Build scanner Docker image\n"
	@printf "    \033[35mai-up\033[0m              Start stack (server + redis)  → \033[38;5;245mhttp://localhost:8002\033[0m\n"
	@printf "    \033[35mai-down\033[0m            Stop stack          \033[38;5;245m│\033[0m \033[35mai-restart\033[0m    Quick restart\n"
	@printf "    \033[35mai-rebuild\033[0m         Full rebuild (no cache) + start\n"
	@printf "    \033[35mai-clean\033[0m           Remove volumes, images, and containers\n"
	@printf "    \033[38;5;245m── Scanning ───────────────────────────────────────────\033[0m\n"
	@printf "    \033[35mai-scan\033[0m     \033[38;5;245mTARGET=x\033[0m  Full autonomous scan (bug-bounty profile)\n"
	@printf "    \033[35mai-recon\033[0m    \033[38;5;245mTARGET=x\033[0m  Recon-only pass\n"
	@printf "    \033[35mai-vuln\033[0m     \033[38;5;245mTARGET=x\033[0m  Vulnerability assessment\n"
	@printf "    \033[35mai-redteam\033[0m  \033[38;5;245mTARGET=x\033[0m  Red team (stealth, high iterations)\n"
	@printf "    \033[38;5;245m── Diagnostics ────────────────────────────────────────\033[0m\n"
	@printf "    \033[35mai-logs\033[0m            Tail container logs \033[38;5;245m│\033[0m \033[35mai-shell\033[0m      Interactive shell\n"
	@printf "    \033[35mai-status\033[0m          Stack & workflow status\n"
	@printf "    \033[35mai-tools\033[0m           Verify installed tool binaries\n"
	@printf "    \033[35mai-validate\033[0m        Validate AI workflow YAML files\n"
	@printf "\n"
	@printf "  \033[1;33m⬡ RELEASE\033[0m\n"
	@printf "    \033[36msnapshot-release\033[0m   Local snapshot     \033[38;5;245m│\033[0m \033[36mlocal-release\033[0m   Mac/Linux arm\n"
	@printf "    \033[36mgithub-release\033[0m     Publish to GitHub  \033[38;5;245m│\033[0m \033[36mrun-github-action\033[0m Trigger CI\n"
	@printf "\n"
	@printf "  \033[1;33m⬡ DATABASE\033[0m\n"
	@printf "    \033[36mdb-seed\033[0m            Seed sample data   \033[38;5;245m│\033[0m \033[36mdb-clean\033[0m  Wipe database\n"
	@printf "    \033[36mdb-migrate\033[0m         Run migrations\n"
	@printf "\n"
