{ caddy }:

caddy.withPlugins {
  # FIXME: https://github.com/caddyserver/transform-encoder/issues/72
  plugins = [
    "github.com/caddyserver/transform-encoder@v0.0.0-20260423033309-ba4124974830"
    "github.com/sjtug/cerberus@v0.4.8"
  ];
  hash = "sha256-pShS64ckH4eVKXJvgDCuDPSrWZb9L8RYjeTqoupRGZE=";
}
