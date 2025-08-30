caddy-update-dist:
	./scripts/download_latest_frontend.sh

caddy-verify-config:
	docker compose run --rm caddy caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile.siyuan
	docker compose run --rm caddy caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile.zhiyuan

# Require Nix to build Python virtualenv
# If Nix isn't available, fallback to uv-managed virtualenv
configure:
	@if command -v nix >/dev/null 2>&1; then \
		echo "--> Nix found, building Python environments with Nix..."; \
		nix build .#pythonEnv-caddy-gen --out-link caddy-gen/.venv --print-out-paths | cachix push sjtug; \
		nix build .#pythonEnv-gateway-gen --out-link gateway-gen/.venv --print-out-paths | cachix push sjtug; \
		nix build .#pythonEnv-integration-test --out-link integration-test/.venv --print-out-paths | cachix push sjtug; \
	else \
		echo "--> Nix not found, falling back to uv..."; \
		(cd caddy-gen && uv sync); \
		(cd gateway-gen && uv sync); \
		(cd integration-test && uv sync); \
	fi

caddy-gen:
	cd caddy-gen && uv run python src/caddy-gen.py -i ../ -o ../caddy --site siyuan,zhiyuan || cd -

caddy-hash-password:
	docker compose run --rm caddy caddy hash-password

caddy-gen-local:
	cd caddy-gen && uv run python src/caddy-gen.py -i ../lug -o ../caddy --site local || cd -

caddy-reload:
	docker compose exec -w /etc/caddy caddy caddy reload

format-config: # You need to install prettier to use this functionality
	prettier -c *.yml

integration-test:
	cd integration-test && uv run pytest || cd -

gateway-gen:
	cd gateway-gen && uv run python src/gateway-gen.py -i ../ -o ../rsync-gateway --site siyuan,zhiyuan || cd -

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
