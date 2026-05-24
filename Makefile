COMPOSE := docker compose
HTPASSWD_FILE := .htpasswd

.PHONY: up watchtower update dashboard-passwd

up:
	mkdir -p ./data
	$(COMPOSE) -f docker-compose.yml up -d --pull always

watchtower:
	COMPOSE_PROFILES=watchtower $(COMPOSE) -f docker-compose.yml up -d --pull always watchtower

update:
	git fetch origin && git checkout -B main origin/main

DASHBOARD_USER ?= hermes

dashboard-passwd:
	$(eval PASS := $(shell openssl rand -base64 16 | tr -d '=+/'))
	@htpasswd -cbB $(HTPASSWD_FILE) "$(DASHBOARD_USER)" "$(PASS)"
	@echo "# $(DASHBOARD_USER):$(PASS)" >> $(HTPASSWD_FILE)
	@echo "user: $(DASHBOARD_USER)"
	@echo "password: $(PASS)"
