#!/bin/sh
set -eu

TEMPLATE=/etc/xray/config.template.json
RUNTIME=/run/xray/config.json

if ! printf '%s\n' "${XRAY_UUID:-}" | grep -Eq \
  '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'; then
  echo "XRAY_UUID is missing or invalid" >&2
  exit 78
fi
if [ "$(grep -o '__XRAY_UUID__' "$TEMPLATE" | wc -l)" -ne 1 ]; then
  echo "xray template must contain exactly one UUID placeholder" >&2
  exit 78
fi

umask 077
sed "s/__XRAY_UUID__/$XRAY_UUID/" "$TEMPLATE" >"$RUNTIME"
unset XRAY_UUID

/usr/bin/xray -test -config "$RUNTIME"
if [ "${XRAY_TEST_ONLY:-}" = 1 ]; then
  exit 0
fi
exec /usr/bin/xray -config "$RUNTIME"
