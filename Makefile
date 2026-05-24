COMPOSE := docker compose
HTPASSWD_FILE := .htpasswd

-include .env

AGENT_DOCKER_SOCKET ?= 0
COMPOSE_FILES := -f docker-compose.yml

ifneq ($(filter 1 true yes on,$(AGENT_DOCKER_SOCKET)),)
COMPOSE_FILES += -f docker-compose.agent-docker.yml
endif

.PHONY: up watchtower update dashboard-passwd

up:
	mkdir -p ./data
	$(COMPOSE) $(COMPOSE_FILES) up -d --pull always

watchtower:
	COMPOSE_PROFILES=watchtower $(COMPOSE) $(COMPOSE_FILES) up -d --pull always watchtower

update:
	git fetch origin && git checkout -B main origin/main

DASHBOARD_USER ?= hermes

dashboard-passwd:
	$(eval PASS := $(shell openssl rand -base64 16 | tr -d '=+/'))
	@htpasswd -cbB $(HTPASSWD_FILE) "$(DASHBOARD_USER)" "$(PASS)"
	@echo "# $(DASHBOARD_USER):$(PASS)" >> $(HTPASSWD_FILE)
	@echo "user: $(DASHBOARD_USER)"
	@echo "password: $(PASS)"
