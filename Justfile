set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# Validate the activated mirror Compose model.
mirror-config site: (_mirror "config" site)

# Build images through the activated mirror Compose model.
mirror-build site: (_mirror "build" site)

# Build and start a complete mirror stack.
mirror-up site: (_mirror "up" site)

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
