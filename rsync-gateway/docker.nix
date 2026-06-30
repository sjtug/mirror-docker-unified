{
  lib,
  nix2container,
  mirror-lib,
  dockerTools,
  rsync-gateway,
}:
let
  inherit (mirror-lib) foldImageLayers;
in
nix2container.buildImage {
  name = "rsync-gateway";
  tag = "latest";

  copyToRoot = [
    dockerTools.caCertificates
  ];

  layers = foldImageLayers [
    { deps = [ rsync-gateway ]; }
  ];

  config = {
    Cmd = [ (lib.getExe' rsync-gateway "rsync-gateway") ];
    WorkingDir = "/app";
    ExposedPorts = {
      "8000/tcp" = { };
    };
  };
}
