SHELL := /bin/bash
.DEFAULT_GOAL := help

help:
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make <target>\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

build: ## Build custom images (plugins/apps baked in)
	docker compose build

up: build ## Start all services
	docker compose up -d

down: ## Stop services
	docker compose down

destroy: ## Stop and remove volumes
	docker compose down -v

logs: ## Tail logs
	docker compose logs -f --tail=200 netbox nautobot jenkins oxidized filebeat

ps: ## Status
	docker compose ps

gen-secrets: ## Generate Django SECRET_KEYs in .env
	python3 scripts/gen_secrets.py .env

bootstrap: ## Create superusers (idempotent)
	bash scripts/bootstrap.sh

urls: ## Print URLs
	@echo -e "\nLocal Access:"
	@echo -e "NetBox:    http://localhost:8080/\nNautobot:  http://localhost:8081/\npgAdmin:   http://localhost:5050/\nRedis Cmd: http://localhost:8082/\nJenkins:   http://localhost:8090/\nOxidized:  http://localhost:8888/\n"
	@echo -e "LAN Access (192.168.5.9):"
	@echo -e "NetBox:    http://192.168.5.9:8080/\nNautobot:  http://192.168.5.9:8081/\npgAdmin:   http://192.168.5.9:5050/\nRedis Cmd: http://192.168.5.9:8082/\nJenkins:   http://192.168.5.9:8090/\nOxidized:  http://192.168.5.9:8888/\n"
	@echo -e "Observability Stack Integration:"
	@echo -e "Elasticsearch: http://192.168.5.13:9200/\nKibana:        http://192.168.5.13:5601/\nGrafana:       http://192.168.5.13:3000/\nPrometheus:    http://192.168.5.13:9090/\nAlertmanager:  http://192.168.5.13:9093/\n"
	@echo -e "Prometheus Config: ./monitoring/prometheus-netmgmt.yml"
