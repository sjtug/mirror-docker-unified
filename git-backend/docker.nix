{
  lib,
  nix2container,
  writeShellScriptBin,
  replaceVars,
  mirror-lib,
  dockerTools,
  nginx,
  git,
  fcgiwrap,
  spawn_fcgi,
}:
let
  inherit (mirror-lib) foldImageLayers;

  nginx-conf = replaceVars ./nginx.conf {
    gitHttpBackend = "${git}/libexec/git-core/git-http-backend";
    fastcgiParams = "${nginx}/conf/fastcgi_params";
  };

  entrypoint = writeShellScriptBin "entrypoint" ''
    set -e
    ${spawn_fcgi}/bin/spawn-fcgi -s /run/fcgi.sock ${fcgiwrap}/bin/fcgiwrap
    exec ${nginx}/bin/nginx -c ${nginx-conf} -g "daemon off;"
  '';
in
nix2container.buildImage {
  name = "git-backend";
  tag = "latest";

  copyToRoot = [
    dockerTools.caCertificates
  ];

  layers = foldImageLayers [
    {
      deps = [
        nginx
        git
        fcgiwrap
        spawn_fcgi
        entrypoint
      ];
    }
  ];

  config = {
    Cmd = [ "${entrypoint}/bin/entrypoint" ];
    ExposedPorts = {
      "80/tcp" = { };
    };
    Volumes = {
      "/git" = { };
    };
  };
}
