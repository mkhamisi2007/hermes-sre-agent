.PHONY: up down restart logs verify-config

REQUIRED_VARS := TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_USERS LLM_BASE_URL LLM_MODEL_NAME KUBECONFIG_PATH

verify-config:
	@test -f .env || (echo "ERROR: .env not found. Run: cp .env.example .env" && exit 1)
	@set -a; . ./.env; set +a; \
	missing=""; \
	for v in $(REQUIRED_VARS); do \
		eval val=\$$$$v; \
		if [ -z "$$val" ]; then missing="$$missing $$v"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo "ERROR: missing required .env values:$$missing"; \
		exit 1; \
	fi
	@test -f "$$(grep '^KUBECONFIG_PATH=' .env | cut -d= -f2-)" || \
		(echo "ERROR: KUBECONFIG_PATH does not point to an existing file" && exit 1)
	@echo "Config OK."

up: verify-config
	@mkdir -p data
	@# Resolve ${VAR} placeholders ourselves rather than relying on Hermes' runtime substitution:
	@# live-tested and found inconsistent (cron jobs resolved model.default correctly, but an
	@# interactive Telegram session sent the literal unsubstituted string to Ollama, causing
	@# "HTTP 400: invalid model name"). Baking in literal values here removes that dependency.
	@set -a; . ./.env; set +a; envsubst < config.yaml > data/config.yaml
	docker compose up -d --build

down:
	docker compose down

restart: down up

logs:
	docker compose logs -f hermes
