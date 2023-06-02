#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

sanitise_uri() {
  local url="${1}"
  url="${url#*://}"          # Remove protocol
  url="${url#*@}"            # Remove user auth
  echo "${url}"
}

# Setup apt-mirror config
cat <<EOF > "apt-mirror_$LUG_name.list"
set base_path    	$LUG_apt_mirror_path/$LUG_name
set mirror_path  	\$base_path/mirror
set skel_path    	\$base_path/skel
set var_path     	\$base_path/var
set run_postmirror    	0
set _autoclean 		1
set defaultarch  	null
EOF

# LUG_source is the base path of all urls, add trailing slash
LUG_source="${LUG_source%/}/"

# LUG_arch is a comma separated list of architectures
IFS="," read -r -a archs <<< "$LUG_arch"

modules=()
# LUG_repo is a comma separated list of (module:arch:components) tuples
IFS=',' read -r -a repos <<< "$LUG_repo"
for repo in "${repos[@]}"; do
    IFS=':' read -r module dist components <<< "$repo"
    module="${module# }"
    modules+=("$module")
    for arch in "${archs[@]}"; do
	echo "deb-$arch $LUG_source$module $dist $components" >> "apt-mirror_$LUG_name.list"
    done
done

IFS=" " read -r -a modules <<< "$(echo "${modules[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
for module in "${modules[@]}"; do
    echo "clean $LUG_source$module" >> "apt-mirror_$LUG_name.list"
done

apt-mirror "apt-mirror_$LUG_name.list"

if [ ! -d "$LUG_path" ]; then
    rel_path=$(sanitise_uri "$LUG_source")
    ln -s "$LUG_apt_mirror_path/$LUG_name/mirror/$rel_path" "$LUG_path"
fi
