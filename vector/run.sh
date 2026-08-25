#!/bin/sh
set -eu

tls_dir=/etc/mirrorz/vector/tls
set -- --config /etc/vector/vector.yaml

if [ -r "$tls_dir/ca.crt" ] && \
   [ -r "$tls_dir/client.crt" ] && \
   [ -r "$tls_dir/client.key" ]; then
  echo "Vector central forwarding enabled: mTLS credentials are present"
  set -- "$@" --config /etc/vector/central-sink.yaml
elif [ "${VECTOR_REQUIRE_CENTRAL_FORWARDING:-false}" = true ]; then
  echo "Vector central forwarding required, but mTLS credentials are incomplete in $tls_dir" >&2
  exit 78
else
  echo "Vector central forwarding disabled: mTLS credentials are incomplete; local metrics remain enabled" >&2
fi

exec vector "$@" --require-healthy true
