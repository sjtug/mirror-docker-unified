#!/bin/bash
set -xe

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

$DIR/pre-git.sh

pushd "$LUG_path"
jq 'setpath(["dl"]; "https://mirror.sjtu.edu.cn/crates.io/crates/{crate}/{crate}-{version}.crate")' config.json > config.json.temp
mv config.json.temp config.json
git config user.name 'SJTUG mirrors'
git config user.email 'mirrors@sjtug.org'
git add .
git commit -m "update config.json" || true
popd

$DIR/post-git.sh
