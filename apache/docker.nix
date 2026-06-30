{
  lib,
  nix2container,
  mirror-lib,
  dockerTools,
  replaceVars,
  apacheHttpd,
}:
let
  inherit (mirror-lib) foldImageLayers;

  httpd-conf = replaceVars ./httpd.conf {
    extraConfig = builtins.readFile ./httpd_config;
  };
in
nix2container.buildImage {
  name = "apache";
  tag = "latest";

  copyToRoot = [
    dockerTools.caCertificates
  ];

  layers = foldImageLayers [
    { deps = [ apacheHttpd ]; }
  ];

  config = {
    Cmd = [
      "${apacheHttpd}/bin/httpd"
      "-f"
      httpd-conf
      "-D"
      "FOREGROUND"
    ];
    ExposedPorts = {
      "80/tcp" = { };
    };
  };
}
