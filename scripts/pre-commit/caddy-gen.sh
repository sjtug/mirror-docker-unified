#!/usr/bin/env bash
# Pre-commit hook: verify generated Caddyfiles are up-to-date with their sources.
#
# Regenerates caddy-gen output to a temporary directory and diffs each file
# against the tracked versions in caddy/.  Exits 1 (blocking commit) when
# any generated file is stale.
#
# The script is idempotent and leaves the working tree untouched.

set -o errexit -o nounset -o pipefail

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -f "$PWD/flake.nix" && -d "$PWD/caddy-gen" ]]; then
  PROJECT_DIR=$PWD
else
  PROJECT_DIR=$(cd -- "$SELF_DIR/../.." && pwd)
fi

cd "$PROJECT_DIR"

# ---- helpers ----------------------------------------------------------------

RED=; GREEN=; BOLD=; RESET=
if [[ -t 2 ]] && command -v tput >/dev/null 2>&1; then
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  BOLD=$(tput bold)
  RESET=$(tput sgr0)
fi

die()   { echo "${RED}${BOLD}ERROR${RESET}${BOLD}: $*${RESET}" >&2; exit 1; }
ok()    { echo "  ${GREEN}ok${RESET}  $*"; }
fail()  { echo "  ${RED}FAIL${RESET} $*"; }

# ---- config -----------------------------------------------------------------

SITES=(siyuan zhiyuan)

# Relative to PROJECT_DIR
GENERATOR_DIR="caddy-gen"
GENERATOR_SCRIPT="src/caddy-gen.py"
INPUT_DIR="."
OUTPUT_DIR="caddy"

GENERATED_FILES=()
for site in "${SITES[@]}"; do
  GENERATED_FILES+=("$OUTPUT_DIR/Caddyfile.$site")
done

# ---- bootstrap venv ---------------------------------------------------------

CADDY_GEN_PYTHON=${CADDY_GEN_PYTHON:-}
if [[ -z "$CADDY_GEN_PYTHON" ]]; then
  echo ":: Setting up Python virtual environment (if needed)..."
  make configure-venv >/dev/null 2>&1 || die "make configure-venv failed"
  CADDY_GEN_PYTHON="$PROJECT_DIR/$GENERATOR_DIR/.venv/bin/python"
fi

[[ -x "$CADDY_GEN_PYTHON" ]] || die "Python interpreter not found: $CADDY_GEN_PYTHON"

# ---- regenerate to temp dir -------------------------------------------------

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo ":: Regenerating Caddyfiles..."
# Build site list: "siyuan,zhiyuan"
SITE_LIST=$(IFS=,; echo "${SITES[*]}")

cd "$GENERATOR_DIR"
"$CADDY_GEN_PYTHON" "$GENERATOR_SCRIPT" \
  -i "$PROJECT_DIR/$INPUT_DIR" \
  -o "$TMPDIR" \
  --site "$SITE_LIST" \
  >/dev/null 2>&1 || die "caddy-gen failed"
cd "$PROJECT_DIR"

# ---- diff each generated file -----------------------------------------------

ANY_FAILURE=0

for site in "${SITES[@]}"; do
  tracked="$PROJECT_DIR/$OUTPUT_DIR/Caddyfile.$site"
  generated="$TMPDIR/Caddyfile.$site"

  if [[ ! -f "$generated" ]]; then
    fail "$tracked — generator did not produce this file"
    ANY_FAILURE=1
    continue
  fi

  if diff -q "$tracked" "$generated" >/dev/null 2>&1; then
    ok "$tracked"
  else
    fail "$tracked — file is stale, run 'make caddy-gen' to regenerate"
    ANY_FAILURE=1
  fi
done

echo ""
if [[ $ANY_FAILURE -eq 0 ]]; then
  echo "${GREEN}All Caddyfiles are up-to-date.${RESET}"
  exit 0
else
  echo "${RED}${BOLD}Some generated files are stale.  Run 'make caddy-gen' and commit the updated files.${RESET}"
  exit 1
fi
