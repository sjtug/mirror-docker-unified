{
  lib,
  nix2container,
  mirror-lib,
  dockerTools,
  caddy,
}:
let
  inherit (mirror-lib) foldImageLayers;
in
nix2container.buildImage {
  name = "caddy";
  tag = "latest";

  copyToRoot = [
    dockerTools.caCertificates
  ];

  layers = foldImageLayers [
    { deps = [ caddy ]; }
  ];

  config = {
    Cmd = [
      "${caddy}/bin/caddy"
      "run"
      "--config"
      "/etc/caddy/Caddyfile"
      "--adapter"
      "caddyfile"
    ];
    ExposedPorts = {
      "80/tcp" = { };
      "443/tcp" = { };
    };
  };
}
