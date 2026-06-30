{
  lib,
  nix2container,
  mirror-lib,
  dockerTools,
  rsync,
}:
let
  inherit (mirror-lib) foldImageLayers;
in
nix2container.buildImage {
  name = "rsyncd";
  tag = "latest";

  copyToRoot = [
    dockerTools.caCertificates
  ];

  layers = foldImageLayers [
    { deps = [ rsync ]; }
  ];

  config = {
    Cmd = [
      "${rsync}/bin/rsync"
      "--daemon"
      "--no-detach"
    ];
    ExposedPorts = {
      "873/tcp" = { };
    };
  };
}
