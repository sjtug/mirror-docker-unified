#!/bin/bash

set -xe

if [ ! -d "${LUG_path}/.git" ]; then
	git clone "$LUG_origin" "$LUG_path"
fi

cd "$LUG_path"
git remote set-url origin "$LUG_origin"
git fetch --prune origin
git remote set-head origin --auto

origin_head="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD)"
default_branch="${origin_head#origin/}"

git checkout -B "$default_branch" "$origin_head"
git branch --set-upstream-to="$origin_head" "$default_branch"
git reset --hard "$origin_head"
git update-server-info
git gc --auto
git repack -a -b -d
