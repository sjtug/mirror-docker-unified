#!/bin/bash
set -xe

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

$DIR/pre-git.sh

pushd "$LUG_path"
yq -i '.archive-mirrors = "https://mirrors.sjtug.sjtu.edu.cn/opam-cache"' repo
git config user.name 'SJTUG mirrors'
git config user.email 'mirrors@sjtug.org'
git add .
git commit -m "update repo" || true
popd

$DIR/post-git.sh
