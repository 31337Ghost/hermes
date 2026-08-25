COMPOSE := docker compose -f docker-compose.yml
HTPASSWD_FILE := .htpasswd

.PHONY: up pull restart logs watchtower update dashboard-passwd browser-up browser-status browser-logs

up:
	mkdir -p ./data ./browser-data
	$(COMPOSE) up -d --pull always --remove-orphans

pull:
	$(COMPOSE) pull

restart:
	$(COMPOSE) up -d --force-recreate browser browser-cdp-proxy agent

logs:
	$(COMPOSE) logs -f --tail=200 agent browser browser-cdp-proxy

watchtower:
	COMPOSE_PROFILES=watchtower $(COMPOSE) up -d --pull always watchtower

update:
	git fetch origin && git checkout -B main origin/main

DASHBOARD_USER ?= hermes

dashboard-passwd:
	$(eval PASS := $(shell openssl rand -base64 16 | tr -d '=+/'))
	@htpasswd -cbB $(HTPASSWD_FILE) "$(DASHBOARD_USER)" "$(PASS)"
	@echo "# $(DASHBOARD_USER):$(PASS)" >> $(HTPASSWD_FILE)
	@echo "user: $(DASHBOARD_USER)"
	@echo "password: $(PASS)"

browser-up: up

browser-status:
	$(COMPOSE) ps browser browser-cdp-proxy

browser-logs:
	$(COMPOSE) logs -f --tail=200 browser browser-cdp-proxy
