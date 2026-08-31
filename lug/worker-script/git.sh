#!/bin/bash

set -euo pipefail

# A bare (mirror) repo is identified by its HEAD file. If the directory is
# missing, empty, or holds a partial/failed clone, remove it and re-clone so
# the worker self-heals instead of failing forever on a stale directory.
if [[ ! -f $LUG_path/HEAD ]]; then
    rm -rf "$LUG_path"
    git clone --mirror "$LUG_source" "$LUG_path"
fi

cd "$LUG_path"

git remote set-url origin "$LUG_source"

if [[ -n "${LUG_target:-}" ]]; then
    if git remote get-url upstream >/dev/null 2>&1; then
        git remote set-url upstream "$LUG_target"
    else
        git remote add upstream "$LUG_target"
    fi
fi

git config --unset-all remote.origin.fetch || true
git config --add remote.origin.fetch "+refs/heads/*:refs/heads/*"
git config --add remote.origin.fetch "+refs/tags/*:refs/tags/*"

git fetch -p origin

# Long-lived mirror clones accumulate loose objects and dead packs; keep the
# on-disk representation compact.
git gc --auto

# dpdk repo contains "remotes/github". We should remove them.
# Pipe failure is guarded by pipefail: a failed for-each-ref aborts the script
# rather than silently feeding an empty update to update-ref.
git for-each-ref --format 'delete %(refname)' refs/remotes | git update-ref --stdin
git for-each-ref --format 'delete %(refname)' refs/pull | git update-ref --stdin

if [[ -n "${LUG_target:-}" ]]; then
    # A generous timeout: killed pushes cannot resume, so a short limit makes
    # slow repos (initial mirror of llvm-project/flutter, big force-pushes)
    # fail on every retry and the upstream diverges silently. 10 minutes
    # bounds a hung push while letting normal incremental pushes through.
    timeout 600 git push --mirror upstream \
        || { echo "[git.sh] WARNING: push to upstream failed (will retry on next sync)" >&2; exit 1; }
fi
