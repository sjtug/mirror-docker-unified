#!/bin/bash

set -xe

if [ ! -d "${LUG_path}/.git" ]; then
	git clone "$LUG_origin" "$LUG_path"
fi

cd "$LUG_path"
git remote set-url origin "$LUG_origin"
git pull --all --rebase || (git reset --hard origin/HEAD && git pull --all --rebase)
git update-server-info
git gc --auto
git repack -a -b -d
