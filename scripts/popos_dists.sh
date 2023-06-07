#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

GREP=${GREP:-grep}

function generate_dists() {
    module=$1
    html=$(curl "https://apt-origin.pop-os.org/$1/dists/")
    
    # Get the list of dists
    dists=($(echo "$html" | $GREP -oP '(?<=<a href=")[^"]*(?=/">)' | $GREP -v '\.\.'))
}

repos=("proprietary" "release" "staging/master" "staging-proprietary")

for repo in "${repos[@]}"; do
    generate_dists "$repo"
    for dist in "${dists[@]}"; do
	echo -n "$repo:$dist:main,"
    done
done
