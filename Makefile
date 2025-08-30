caddy-update-dist:
	./scripts/download_latest_frontend.sh

caddy-verify-config:
	docker compose run --rm caddy caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile.siyuan
	docker compose run --rm caddy caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile.zhiyuan

# Require UV to build Python virtualenv
configure:
	@if command -v uv >/dev/null 2>&1; then \
		echo "Configure Python environment with uv"; \
		(cd caddy-gen && uv sync); \
		(cd gateway-gen && uv sync); \
		(cd integration-test && uv sync); \
	else \
		echo "ERROR: uv not found"; \
	fi

caddy-gen:
	cd caddy-gen && .venv/bin/python src/caddy-gen.py -i ../ -o ../caddy --site siyuan,zhiyuan || cd -

caddy-hash-password:
	docker compose run --rm caddy caddy hash-password

caddy-gen-local:
	cd caddy-gen && .venv/bin/python src/caddy-gen.py -i ../lug -o ../caddy --site local || cd -

caddy-reload:
	docker compose exec -w /etc/caddy caddy caddy reload

format-config: # You need to install prettier to use this functionality
	prettier -c *.yml

integration-test:
	cd integration-test && .venv/bin/pytest || cd -

gateway-gen:
	cd gateway-gen && .venv/bin/python src/gateway-gen.py -i ../ -o ../rsync-gateway --site siyuan,zhiyuan || cd -

up:
	docker compose up -d --build

up-siyuan:
	docker compose -f docker-compose.yml -f docker-compose.siyuan.yml up -d --build

up-zhiyuan:
	docker compose -f docker-compose.yml -f docker-compose.zhiyuan.yml up -d --build

build-siyuan:
	docker compose -f docker-compose.yml -f docker-compose.siyuan.yml build

build-zhiyuan:
	docker compose -f docker-compose.yml -f docker-compose.zhiyuan.yml build

build:
	docker compose build

.PHONY: caddy-gen gateway-gen integration-test
