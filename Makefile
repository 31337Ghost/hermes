COMPOSE := docker compose
BROWSER_COMPOSE := $(COMPOSE) -f docker-compose.yml -f docker-compose.browser.yml
HTPASSWD_FILE := .htpasswd

.PHONY: up watchtower update dashboard-passwd browser-up browser-status browser-logs browser-stop

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

browser-up:
	mkdir -p ./browser-data
	$(BROWSER_COMPOSE) up -d browser browser-cdp-proxy agent

browser-status:
	$(BROWSER_COMPOSE) ps browser browser-cdp-proxy

browser-logs:
	$(BROWSER_COMPOSE) logs -f --tail=200 browser browser-cdp-proxy

browser-stop:
	$(BROWSER_COMPOSE) stop browser browser-cdp-proxy
