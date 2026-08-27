set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

g-storage-dir := "monitor/g-storage"
nix-flags := env_var_or_default("NIX_FLAGS", "--accept-flake-config --option warn-dirty false")
g-storage-compose := "sudo nerdctl --address /run/containerd/containerd.sock --namespace default compose --project-directory monitor/g-storage --project-name docker-prometheus-grafana -f monitor/g-storage/docker-compose.yml"

default:
    @just --list

# Download the current frontend distribution.
caddy-update-dist:
    ./scripts/download_latest_frontend.sh

# Validate the generated Caddy configurations in containers.
caddy-verify-config:
    docker compose run --rm caddy caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile.siyuan
    docker compose run --rm caddy caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile.zhiyuan

# Validate edge Vector and xray configuration contracts.
vector-check:
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/check-vector.sh
    python3 ./scripts/validate-mirror-xray-config.py --template xray/config.edge.json
    for site in siyuan zhiyuan; do
      grep -Eq '^XRAY_UUID=ENC\[' "secrets/$site/xray.env.sops"
      sops filestatus --input-type dotenv "secrets/$site/xray.env.sops" |
        grep -Fq '"encrypted":true'
    done

# Prepare the Python workspace used by configuration generators and tests.
configure-venv:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v uv >/dev/null 2>&1; then
      echo "Configure Python virtual environment with uv"
      uv sync --config-file /dev/null --default-index https://pypi.org/simple \
        --locked --all-packages --no-install-workspace
    elif command -v nix >/dev/null 2>&1; then
      echo "Configure Python virtual environment with uv2nix"
      nix build .#python-workspace --out-link .venv --option warn-dirty false
    else
      echo "uv or nix is required" >&2
      exit 1
    fi
    ln -sfn ../.venv caddy-gen/.venv
    ln -sfn ../.venv gateway-gen/.venv
    ln -sfn ../.venv integration-test/.venv

# Generate Caddy configuration for both production sites.
caddy-gen: configure-venv
    (cd caddy-gen && .venv/bin/python src/caddy-gen.py -i ../ -o ../caddy --site siyuan,zhiyuan)

# Generate local Caddy configuration.
caddy-gen-local: configure-venv
    (cd caddy-gen && .venv/bin/python src/caddy-gen.py -i ../lug -o ../caddy --site local)

# Generate rsync-gateway configuration for both production sites.
gateway-gen: configure-venv
    (cd gateway-gen && .venv/bin/python src/gateway-gen.py -i ../ -o ../rsync-gateway --site siyuan,zhiyuan)

# Hash a Caddy password interactively.
caddy-hash-password:
    docker compose run --rm caddy caddy hash-password

# Reload the running Caddy service.
caddy-reload:
    docker compose exec -w /etc/caddy caddy caddy reload

# Check top-level YAML formatting with Prettier.
format-config:
    prettier -c *.yml

# Run the integration test suite.
integration-test: configure-venv
    (cd integration-test && .venv/bin/pytest)

# Build and start the default development stack.
up: caddy-gen gateway-gen
    docker compose up -d --build

# Build the default development stack.
build: caddy-gen gateway-gen
    docker compose build

# Decrypt g-storage host-local secrets to ignored runtime files.
g-storage-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    dir={{ quote(g-storage-dir) }}
    identity=${G_STORAGE_SOPS_SSH_KEY_FILE:-/etc/ssh/ssh_host_ed25519_key}
    [[ -r "$identity" ]] || {
      echo "SOPS SSH identity is not readable: $identity" >&2
      exit 1
    }
    decrypt() {
      local source=$1 output=$2
      [[ -f "$source" ]] || return 0
      SOPS_AGE_SSH_PRIVATE_KEY_FILE="$identity" sops -d --output "$output" "$source"
      chmod 600 "$output"
    }
    decrypt "$dir/g-storage.sops.env" "$dir/.env"
    decrypt "$dir/bot.sops.env" "$dir/bot.env"
    decrypt "$dir/xray/config.sops.json" "$dir/xray/config.json"

# Render g-storage service configuration after validating runtime secrets.
g-storage-render: g-storage-secrets
    #!/usr/bin/env bash
    set -euo pipefail
    dir={{ quote(g-storage-dir) }}
    for path in "$dir/.env" "$dir/xray/config.json"; do
      [[ -f "$path" ]] || {
        echo "Required runtime configuration is missing: $path" >&2
        exit 1
      }
      [[ $(stat -c %a "$path") == 600 ]] || {
        echo "$path must have mode 0600" >&2
        exit 1
      }
    done
    if [[ -e "$dir/bot.env" && $(stat -c %a "$dir/bot.env") != 600 ]]; then
      echo "$dir/bot.env must have mode 0600" >&2
      exit 1
    fi
    (cd "$dir" && ./scripts/render-monitor-configs.py && ./scripts/render-prometheus-config.py)

# Render and validate the rootful g-storage Compose model.
g-storage-config: g-storage-render
    {{ g-storage-compose }} config --quiet

# Validate edge and g-storage monitoring configuration.
g-storage-check: vector-check
    nix develop {{ nix-flags }} -c {{ g-storage-dir }}/scripts/check-configs.sh
    nix develop {{ nix-flags }} -c {{ g-storage-dir }}/scripts/check-hotspot-analytics.sh

# Verify host prerequisites for starting the g-storage stack.
g-storage-preflight: g-storage-check g-storage-config
    #!/usr/bin/env bash
    set -euo pipefail
    nerdctl_bin=$(command -v nerdctl)
    sudo "$nerdctl_bin" --address /run/containerd/containerd.sock --namespace default \
      network inspect metacubexd_default >/dev/null
    sudo install -d -m 0750 -o 101 -g 101 /var/lib/mirror-monitor/hotspot-clickhouse
    sudo install -d -m 0750 -o 0 -g 0 /var/lib/mirror-monitor/hotspot-vector
    [[ -d /var/lib/mirror-monitor/textfile_collector ]] || {
      echo "Run 'just g-storage-enable-collectors' first" >&2
      exit 1
    }
    sudo systemctl is-enabled --quiet mirror-monitor-g-storage-textfile.timer
    sudo systemctl is-active --quiet mirror-monitor-g-storage-textfile.timer

# Build the custom Grafana image.
g-storage-build: g-storage-config
    {{ g-storage-compose }} build grafana

# Start the complete rootful g-storage stack without pulling or building.
g-storage-up: g-storage-preflight
    {{ g-storage-compose }} up -d --no-build --pull never
    {{ g-storage-compose }} exec -T clickhouse clickhouse-client --multiquery < {{ g-storage-dir }}/config/clickhouse/schema.sql

# Show g-storage Compose status.
g-storage-ps:
    {{ g-storage-compose }} ps

# Show recent logs from the monitoring services.
g-storage-logs:
    {{ g-storage-compose }} logs --tail=100 prometheus alertmanager blackbox-exporter node-exporter grafana clickhouse loki vector

# Recreate g-storage containers after atomically replacing configuration files.
g-storage-reload: g-storage-check g-storage-config
    {{ g-storage-compose }} up -d --force-recreate --no-build --pull never
    {{ g-storage-compose }} exec -T clickhouse clickhouse-client --multiquery < {{ g-storage-dir }}/config/clickhouse/schema.sql

# Show g-storage collector timers and the latest collector result.
g-storage-collector-status:
    sudo systemctl list-timers 'mirror-monitor-*-textfile.timer' --no-pager
    sudo systemctl show mirror-monitor-g-storage-textfile.service -p Result -p ExecMainStatus -p ExecMainStartTimestamp --no-pager

# Install g-storage's local textfile collector and remove retired repository polling.
g-storage-install-collectors:
    #!/usr/bin/env bash
    set -euo pipefail
    dir={{ quote(g-storage-dir) }}
    sudo install -d -m 0755 /var/lib/mirror-monitor/textfile_collector /etc/mirror-monitor
    if [[ ! -e /etc/mirror-monitor/g-storage.env ]]; then
      sudo install -m 0644 "$dir/scripts/systemd/g-storage.env.example" /etc/mirror-monitor/g-storage.env
    fi
    sudo install -m 0755 "$dir/scripts/mirror-monitor-collect-g-storage.sh" /usr/local/sbin/mirror-monitor-collect-g-storage.sh
    for unit in "$dir"/scripts/systemd/*.{service,timer}; do
      sudo install -m 0644 "$unit" "/etc/systemd/system/${unit##*/}"
    done
    sudo systemctl disable --now mirror-monitor-repo-stats-textfile.timer 2>/dev/null || true
    sudo systemctl stop mirror-monitor-repo-stats-textfile.service 2>/dev/null || true
    sudo rm -f \
      /etc/systemd/system/mirror-monitor-repo-stats-textfile.{service,timer} \
      /usr/local/sbin/mirror-monitor-collect-repo-stats.sh \
      /var/lib/mirror-monitor/textfile_collector/mirror_repo_stats_siyuan.prom \
      /etc/mirror-monitor/ssh/mirror_siyuan_repo_stats \
      /etc/mirror-monitor/ssh/mirror_siyuan_repo_stats.pub
    sudo systemctl daemon-reload

# Install and enable g-storage's local textfile collector.
g-storage-enable-collectors: g-storage-install-collectors
    sudo systemctl enable --now mirror-monitor-g-storage-textfile.timer
    sudo systemctl start mirror-monitor-g-storage-textfile.service

# Install mirror-host textfile collectors.
mirror-install-collectors site: caddy-gen
    #!/usr/bin/env bash
    set -euo pipefail
    site={{ quote(site) }}
    case "$site" in siyuan | zhiyuan) ;; *) echo "site must be siyuan or zhiyuan" >&2; exit 2 ;; esac
    sudo systemctl cat node_exporter.service node_exporter.socket >/dev/null
    grep -Fq -- '--collector.textfile.directory /var/lib/node_exporter/textfile_collector' /etc/sysconfig/node_exporter || {
      echo "node_exporter textfile directory is not configured" >&2
      exit 1
    }
    sudo install -d -m 0755 /var/lib/node_exporter/textfile_collector /etc/mirror-monitor
    sudo install -m 0644 "caddy/local-repositories.$site.txt" /etc/mirror-monitor/local-repositories.txt
    sudo install -m 0755 "{{ g-storage-dir }}/scripts/remote/mirror-repo-size-collector.py" /usr/local/bin/mirror-repo-size-collector
    for unit in "{{ g-storage-dir }}/scripts/systemd/$site"/mirror-repo-size-textfile.{service,timer}; do
      sudo install -m 0644 "$unit" "/etc/systemd/system/${unit##*/}"
    done
    if [[ "$site" == siyuan ]]; then
      sudo install -m 0755 "{{ g-storage-dir }}/scripts/remote/mirror-siyuan-iscsi-metrics" /usr/local/sbin/mirror-siyuan-iscsi-metrics
      for unit in "{{ g-storage-dir }}/scripts/systemd/siyuan"/mirror-siyuan-iscsi-textfile.{service,timer}; do
        sudo install -m 0644 "$unit" "/etc/systemd/system/${unit##*/}"
      done
    fi
    sudo rm -f /var/lib/node_exporter/textfile_collector/mirror_caddy_repo_traffic.prom
    sudo systemctl daemon-reload

# Install and enable mirror-host textfile collectors.
mirror-enable-collectors site: (mirror-install-collectors site)
    #!/usr/bin/env bash
    set -euo pipefail
    site={{ quote(site) }}
    timers=(mirror-repo-size-textfile.timer)
    services=(mirror-repo-size-textfile.service)
    if [[ "$site" == siyuan ]]; then
      timers+=(mirror-siyuan-iscsi-textfile.timer)
      services+=(mirror-siyuan-iscsi-textfile.service)
    fi
    sudo systemctl enable --now "${timers[@]}"
    sudo systemctl start --no-block "${services[@]}"
    sudo systemctl is-enabled --quiet node_exporter.socket
    sudo systemctl is-active --quiet node_exporter.socket

# Validate the activated mirror Compose model.
mirror-config site: (_mirror "config" site)

# Build images through the activated mirror Compose model.
mirror-build site: caddy-gen gateway-gen (_mirror "build" site)

# Build and start a complete mirror stack.
mirror-up site: caddy-gen gateway-gen (_mirror "up" site)

# Recreate only xray and verify that door 5104 is listening.
mirror-tunnel-reload site: (_mirror "tunnel-reload" site)

# Show xray, Vector, and disk-buffer status without decrypting secrets.
mirror-tunnel-status site: (_mirror "tunnel-status" site)

[private]
_mirror action site:
    #!/usr/bin/env bash
    set -euo pipefail

    action={{ quote(action) }}
    site={{ quote(site) }}
    repo_root={{ quote(justfile_directory()) }}

    case "$site" in
      siyuan | zhiyuan) ;;
      *)
        echo "site must be siyuan or zhiyuan" >&2
        exit 2
        ;;
    esac

    deploy_dir="/opt/mirror-docker-$site"
    if [[ ! -d "$deploy_dir" || "$(realpath "$repo_root")" != "$(realpath "$deploy_dir")" ]]; then
      echo "Run this recipe from $deploy_dir" >&2
      exit 1
    fi

    xray_env="$deploy_dir/secrets/$site/xray.env.sops"
    identity=${MIRROR_SOPS_SSH_KEY_FILE:-/etc/ssh/ssh_host_ed25519_key}
    for path in \
      "$xray_env" \
      "$deploy_dir/docker-compose.yml" \
      "$deploy_dir/docker-compose.mirror.yml" \
      "$deploy_dir/docker-compose.$site.yml" \
      "$deploy_dir/xray/config.edge.json" \
      "$deploy_dir/xray/run-edge.sh"; do
      [[ -f "$path" ]] || {
        echo "Required deployment file not found: $path" >&2
        exit 1
      }
    done

    compose=(
      docker compose
      --project-name "mirror-docker-$site"
      --project-directory "$deploy_dir"
      -f "$deploy_dir/docker-compose.yml"
      -f "$deploy_dir/docker-compose.mirror.yml"
      -f "$deploy_dir/docker-compose.$site.yml"
    )

    if [[ "$action" == tunnel-status ]]; then
      "${compose[@]}" ps tunnel vector
      "${compose[@]}" exec -T tunnel sh -c \
        "grep -H ':13F0 ' /proc/net/tcp /proc/net/tcp6"
      "${compose[@]}" exec -T vector sh -c \
        "du -sh /var/lib/vector/buffer/v2/* 2>/dev/null || true"
      exit 0
    fi

    command -v sops >/dev/null || {
      echo "sops is required" >&2
      exit 1
    }
    [[ -r "$identity" ]] || {
      echo "SOPS SSH identity is not readable: $identity" >&2
      exit 1
    }

    printf -v compose_command '%q ' "${compose[@]}"
    case "$action" in
      config)
        compose_command+="--env-file {} config --quiet"
        ;;
      build)
        compose_command+="--env-file {} build"
        ;;
      up)
        compose_command+="--env-file {} up -d --build"
        ;;
      tunnel-reload)
        compose_command+="--env-file {} up -d --no-deps --force-recreate --no-build --pull never tunnel"
        ;;
      *)
        echo "Unknown mirror action: $action" >&2
        exit 2
        ;;
    esac

    SOPS_AGE_SSH_PRIVATE_KEY_FILE="$identity" \
      SOPS_DECRYPTION_ORDER=age \
      sops exec-file --no-fifo \
      --input-type dotenv --output-type dotenv \
      "$xray_env" "$compose_command"

    if [[ "$action" != tunnel-reload ]]; then
      exit 0
    fi
    for _ in {1..15}; do
      if "${compose[@]}" exec -T tunnel sh -c \
        "grep -q ':13F0 ' /proc/net/tcp /proc/net/tcp6"; then
        echo "$site xray door 5104 is listening"
        exit 0
      fi
      sleep 1
    done
    "${compose[@]}" logs --tail=50 tunnel
    echo "$site xray door 5104 did not become ready" >&2
    exit 1
