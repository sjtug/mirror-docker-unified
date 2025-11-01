SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
# MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

# Replace <TAB> usage with block character `>`
ifeq ($(origin .RECIPEPREFIX), undefined)
  $(error This Make does not support .RECIPEPREFIX. Please use GNU Make 4.0 or later)
endif
.RECIPEPREFIX = >

# `make up/build DEV=1` to bypass config generation
COMPOSE_TASK_DEPS := $(if $(DEV),,caddy-gen gateway-gen)


caddy-update-dist:
> ./scripts/download_latest_frontend.sh

caddy-verify-config:
> docker compose run --rm caddy caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile.siyuan
> docker compose run --rm caddy caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile.zhiyuan

# Require UV to build Python virtualenv
configure-venv:
> @if command -v uv >/dev/null 2>&1; then \
>   echo "Configure Python virtual environment with uv"; \
>   uv sync --directory caddy-gen; \
>   uv sync --directory gateway-gen; \
>   uv sync --directory integration-test; \
> elif command -v nix >/dev/null 2>&1; then \
>   echo "Configure Python virtual environment with uv2nix"; \
>   eval "$$(nix eval --raw .\#devShells.x86_64-linux.default.shellHook --option warn-dirty false)"; \
> else \
>   echo "ERROR: uv or nix not found"; \
> fi

caddy-gen: configure-venv
> cd caddy-gen && .venv/bin/python src/caddy-gen.py -i ../ -o ../caddy --site siyuan,zhiyuan || cd -

caddy-hash-password:
> docker compose run --rm caddy caddy hash-password

caddy-gen-local: configure-venv
> cd caddy-gen && .venv/bin/python src/caddy-gen.py -i ../lug -o ../caddy --site local || cd -

caddy-reload:
> docker compose exec -w /etc/caddy caddy caddy reload

format-config: # You need to install prettier to use this functionality
> prettier -c *.yml

integration-test: configure-venv
> cd integration-test && .venv/bin/pytest || cd -

gateway-gen: configure-venv
> cd gateway-gen && .venv/bin/python src/gateway-gen.py -i ../ -o ../rsync-gateway --site siyuan,zhiyuan || cd -

up: $(COMPOSE_TASK_DEPS)
> docker compose up -d --build

up-siyuan: $(COMPOSE_TASK_DEPS)
> docker compose -f docker-compose.yml -f docker-compose.siyuan.yml up -d --build

up-zhiyuan: $(COMPOSE_TASK_DEPS)
> docker compose -f docker-compose.yml -f docker-compose.zhiyuan.yml up -d --build

build: $(COMPOSE_TASK_DEPS)
> docker compose build

build-siyuan: $(COMPOSE_TASK_DEPS)
> docker compose -f docker-compose.yml -f docker-compose.siyuan.yml build

build-zhiyuan: $(COMPOSE_TASK_DEPS)
> docker compose -f docker-compose.yml -f docker-compose.zhiyuan.yml build

.PHONY: caddy-gen gateway-gen integration-test
