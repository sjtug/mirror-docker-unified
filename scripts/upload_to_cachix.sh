#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
SOPS_FILE=$REPO_ROOT/secrets/cachix.sops.env

# The quoted body is evaluated by the shell started by sops.
# shellcheck disable=SC2016
exec sops exec-env --same-process "$SOPS_FILE" '
  set -eu
  cd "$REPO_ROOT"

  input_paths=$(
    nix flake archive --json --option warn-dirty false \
      | jq -er ".inputs[].path"
  )
  printf "%s\n" "$input_paths" | cachix push sjtug

  nix-fast-build \
    --flake ".#checks.x86_64-linux" \
    --option warn-dirty false \
    --option accept-flake-config true \
    --no-nom \
    --cachix-cache sjtug

  nix-fast-build \
    --flake ".#packages.x86_64-linux" \
    --option warn-dirty false \
    --option accept-flake-config true \
    --no-nom \
    --cachix-cache sjtug
'
