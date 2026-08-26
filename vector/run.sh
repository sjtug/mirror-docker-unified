#!/bin/sh
set -eu

mirrorz_tls_dir=/etc/mirrorz/vector/tls
set -- --config /etc/vector/vector.yaml

if [ -r "$mirrorz_tls_dir/ca.crt" ] && \
   [ -r "$mirrorz_tls_dir/client.crt" ] && \
   [ -r "$mirrorz_tls_dir/client.key" ]; then
  echo "Vector MirrorZ forwarding enabled: mTLS credentials are present"
  set -- "$@" --config /etc/vector/central-sink.yaml
elif [ "${VECTOR_REQUIRE_CENTRAL_FORWARDING:-false}" = true ]; then
  echo "Vector MirrorZ forwarding required, but mTLS credentials are incomplete in $mirrorz_tls_dir" >&2
  exit 78
else
  echo "Vector MirrorZ forwarding disabled: mTLS credentials are incomplete; local metrics remain enabled" >&2
fi

exec vector "$@" --require-healthy true
