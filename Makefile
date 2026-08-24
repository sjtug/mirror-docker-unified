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

SUDO ?= sudo
NIX_FLAGS ?= --accept-flake-config --option warn-dirty false
G_STORAGE_DIR ?= monitor/g-storage
G_STORAGE_COMPOSE = $(SUDO) nerdctl --address /run/containerd/containerd.sock --namespace default compose --project-directory $(G_STORAGE_DIR) --project-name docker-prometheus-grafana -f $(G_STORAGE_DIR)/docker-compose.yml
MIRROR_SITE ?=


caddy-update-dist:
> ./scripts/download_latest_frontend.sh

caddy-verify-config:
> docker compose run --rm caddy caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile.siyuan
> docker compose run --rm caddy caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile.zhiyuan

vector-check:
> ./scripts/check-vector.sh

# Require UV to build Python virtualenv
configure-venv:
> @if command -v uv >/dev/null 2>&1; then \
>   echo "Configure Python virtual environment with uv"; \
>   uv sync --config-file /dev/null --default-index https://pypi.org/simple --locked --all-packages --no-install-workspace; \
>   ln -sfn ../.venv caddy-gen/.venv; \
>   ln -sfn ../.venv gateway-gen/.venv; \
>   ln -sfn ../.venv integration-test/.venv; \
> elif command -v nix >/dev/null 2>&1; then \
>   echo "Configure Python virtual environment with uv2nix"; \
>   nix build .\#python-workspace --out-link .venv --option warn-dirty false ; \
>   ln -sfn ../.venv caddy-gen/.venv; \
>   ln -sfn ../.venv gateway-gen/.venv; \
>   ln -sfn ../.venv integration-test/.venv; \
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


g-storage-secrets:
> # Decrypt with the host SSH key as an age identity when available.
> if [ -r /etc/ssh/ssh_host_ed25519_key ]; then
>   export SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/ssh/ssh_host_ed25519_key
> fi
> if [ -f $(G_STORAGE_DIR)/g-storage.sops.env ]; then
>   sops -d --output $(G_STORAGE_DIR)/.env $(G_STORAGE_DIR)/g-storage.sops.env
>   chmod 600 $(G_STORAGE_DIR)/.env
> fi
> if [ -f $(G_STORAGE_DIR)/bot.sops.env ]; then
>   sops -d --output $(G_STORAGE_DIR)/bot.env $(G_STORAGE_DIR)/bot.sops.env
>   chmod 600 $(G_STORAGE_DIR)/bot.env
> fi
> if [ -f $(G_STORAGE_DIR)/xray/config.sops.json ]; then
>   sops -d --output $(G_STORAGE_DIR)/xray/config.json $(G_STORAGE_DIR)/xray/config.sops.json
>   chmod 600 $(G_STORAGE_DIR)/xray/config.json
> fi


g-storage-source-preflight: g-storage-secrets
> @test -f $(G_STORAGE_DIR)/.env || { echo "Copy $(G_STORAGE_DIR)/.env.example to $(G_STORAGE_DIR)/.env and set deployment values" >&2; exit 1; }
> @test -f $(G_STORAGE_DIR)/xray/config.json || { echo "Create $(G_STORAGE_DIR)/xray/config.json from the example or the existing host-local config" >&2; exit 1; }
> @test "$$(stat -c %a $(G_STORAGE_DIR)/.env)" = 600 || { echo "$(G_STORAGE_DIR)/.env must have mode 0600" >&2; exit 1; }
> @test "$$(stat -c %a $(G_STORAGE_DIR)/xray/config.json)" = 600 || { echo "$(G_STORAGE_DIR)/xray/config.json must have mode 0600" >&2; exit 1; }
> if [ -e $(G_STORAGE_DIR)/bot.env ]; then
>   test "$$(stat -c %a $(G_STORAGE_DIR)/bot.env)" = 600 || { echo "$(G_STORAGE_DIR)/bot.env must have mode 0600" >&2; exit 1; }
> fi


g-storage-render: g-storage-source-preflight
> cd $(G_STORAGE_DIR)
> ./scripts/render-monitor-configs.py
> ./scripts/render-prometheus-config.py


g-storage-config: g-storage-render
> $(G_STORAGE_COMPOSE) config --quiet


g-storage-check:
> nix develop $(NIX_FLAGS) -c $(G_STORAGE_DIR)/scripts/check-configs.sh


g-storage-preflight: g-storage-check g-storage-config
> $(SUDO) $(shell command -v nerdctl 2>/dev/null || printf nerdctl) --address /run/containerd/containerd.sock --namespace default network inspect metacubexd_default >/dev/null
> @test -d /var/lib/mirror-monitor/textfile_collector || { echo "Run 'make g-storage-enable-collectors' first" >&2; exit 1; }
> $(SUDO) systemctl is-enabled --quiet mirror-monitor-g-storage-textfile.timer
> $(SUDO) systemctl is-active --quiet mirror-monitor-g-storage-textfile.timer


g-storage-build: g-storage-config
> $(G_STORAGE_COMPOSE) build grafana


g-storage-up: g-storage-preflight
> $(G_STORAGE_COMPOSE) up -d --no-build --pull never


g-storage-ps:
> $(G_STORAGE_COMPOSE) ps


g-storage-logs:
> $(G_STORAGE_COMPOSE) logs --tail=100 prometheus alertmanager blackbox-exporter node-exporter grafana loki vector


g-storage-reload: g-storage-check g-storage-config
> # Renderers replace files atomically, so recreate containers to refresh their bind mounts.
> $(G_STORAGE_COMPOSE) up -d --force-recreate --no-build --pull never


g-storage-collector-status:
> $(SUDO) systemctl list-timers 'mirror-monitor-*-textfile.timer' --no-pager
> $(SUDO) systemctl show mirror-monitor-g-storage-textfile.service \
>   -p Result -p ExecMainStatus -p ExecMainStartTimestamp --no-pager


g-storage-install-collectors:
> $(SUDO) install -d -m 0755 /var/lib/mirror-monitor/textfile_collector
> $(SUDO) install -d -m 0755 /etc/mirror-monitor
> if [ ! -e /etc/mirror-monitor/g-storage.env ]; then
>   $(SUDO) install -m 0644 $(G_STORAGE_DIR)/scripts/systemd/g-storage.env.example /etc/mirror-monitor/g-storage.env
> fi
> $(SUDO) install -m 0755 $(G_STORAGE_DIR)/scripts/mirror-monitor-collect-g-storage.sh /usr/local/sbin/mirror-monitor-collect-g-storage.sh
> for unit in $(G_STORAGE_DIR)/scripts/systemd/*.{service,timer}; do
>   $(SUDO) install -m 0644 "$$unit" "/etc/systemd/system/$${unit##*/}"
> done
> # Repository sizes now run locally on the mirror hosts.
> $(SUDO) systemctl disable --now mirror-monitor-repo-stats-textfile.timer 2>/dev/null || true
> $(SUDO) systemctl stop mirror-monitor-repo-stats-textfile.service 2>/dev/null || true
> $(SUDO) rm -f \
>   /etc/systemd/system/mirror-monitor-repo-stats-textfile.{service,timer} \
>   /usr/local/sbin/mirror-monitor-collect-repo-stats.sh \
>   /var/lib/mirror-monitor/textfile_collector/mirror_repo_stats_siyuan.prom \
>   /etc/mirror-monitor/ssh/mirror_siyuan_repo_stats \
>   /etc/mirror-monitor/ssh/mirror_siyuan_repo_stats.pub
> $(SUDO) systemctl daemon-reload


g-storage-enable-collectors: g-storage-install-collectors
> $(SUDO) systemctl enable --now mirror-monitor-g-storage-textfile.timer
> $(SUDO) systemctl start mirror-monitor-g-storage-textfile.service


mirror-install-collectors: caddy-gen
> case "$(MIRROR_SITE)" in siyuan|zhiyuan) ;; *) echo "Set MIRROR_SITE=siyuan or MIRROR_SITE=zhiyuan" >&2; exit 2 ;; esac
> $(SUDO) systemctl cat node_exporter.service node_exporter.socket >/dev/null
> grep -Fq -- '--collector.textfile.directory /var/lib/node_exporter/textfile_collector' /etc/sysconfig/node_exporter || {
>   echo "node_exporter is not configured for /var/lib/node_exporter/textfile_collector" >&2
>   exit 1
> }
> $(SUDO) install -d -m 0755 /var/lib/node_exporter/textfile_collector /etc/mirror-monitor
> $(SUDO) install -m 0644 caddy/local-repositories.$(MIRROR_SITE).txt /etc/mirror-monitor/local-repositories.txt
> $(SUDO) install -m 0755 $(G_STORAGE_DIR)/scripts/remote/mirror-repo-size-collector.py /usr/local/bin/mirror-repo-size-collector
> for unit in $(G_STORAGE_DIR)/scripts/systemd/$(MIRROR_SITE)/mirror-repo-size-textfile.{service,timer}; do
>   $(SUDO) install -m 0644 "$$unit" "/etc/systemd/system/$${unit##*/}"
> done
> if [ "$(MIRROR_SITE)" = siyuan ]; then
>   $(SUDO) install -m 0755 $(G_STORAGE_DIR)/scripts/remote/mirror-siyuan-iscsi-metrics /usr/local/sbin/mirror-siyuan-iscsi-metrics
>   for unit in $(G_STORAGE_DIR)/scripts/systemd/siyuan/mirror-siyuan-iscsi-textfile.{service,timer}; do
>     $(SUDO) install -m 0644 "$$unit" "/etc/systemd/system/$${unit##*/}"
>   done
> fi
> # Remove the stale one-shot Docker-log collector output superseded by edge Vector.
> $(SUDO) rm -f /var/lib/node_exporter/textfile_collector/mirror_caddy_repo_traffic.prom
> $(SUDO) systemctl daemon-reload


mirror-enable-collectors: mirror-install-collectors
> timers=(mirror-repo-size-textfile.timer)
> services=(mirror-repo-size-textfile.service)
> if [ "$(MIRROR_SITE)" = siyuan ]; then
>   timers+=(mirror-siyuan-iscsi-textfile.timer)
>   services+=(mirror-siyuan-iscsi-textfile.service)
> fi
> $(SUDO) systemctl enable --now "$${timers[@]}"
> $(SUDO) systemctl start --no-block "$${services[@]}"
> $(SUDO) systemctl is-enabled --quiet node_exporter.socket
> $(SUDO) systemctl is-active --quiet node_exporter.socket


mirror-install-repo-size-collector: mirror-install-collectors


mirror-enable-repo-size-collector: mirror-enable-collectors


.PHONY: caddy-gen caddy-verify-config vector-check gateway-gen integration-test \
  g-storage-secrets g-storage-source-preflight g-storage-render g-storage-config \
  g-storage-check g-storage-preflight g-storage-build g-storage-up g-storage-ps \
  g-storage-logs g-storage-reload g-storage-collector-status \
  g-storage-install-collectors g-storage-enable-collectors \
  mirror-install-collectors mirror-enable-collectors \
  mirror-install-repo-size-collector mirror-enable-repo-size-collector
