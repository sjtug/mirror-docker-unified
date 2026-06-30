{
  lib,
  nix2container,
  mirror-lib,
  dockerTools,
  runCommand,
  mirror-intel,
}:
let
  inherit (mirror-lib) foldImageLayers;

  rootfs = runCommand "mirror-intel-rootfs" { } ''
    install -Dm0644 ${./Rocket.toml} $out/app/Rocket.toml
  '';
in
nix2container.buildImage {
  name = "mirror-intel";
  tag = "latest";

  copyToRoot = [
    dockerTools.caCertificates
    rootfs
  ];

  layers = foldImageLayers [
    { deps = [ mirror-intel ]; }
  ];

  config = {
    Cmd = [ (lib.getExe' mirror-intel "mirror-intel") ];
    Env = [ "ROCKET_TOML_PATH=/app/Rocket.toml" ];
    WorkingDir = "/app";
    ExposedPorts = {
      "8000/tcp" = { };
    };
  };
}
