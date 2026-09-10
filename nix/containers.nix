# Container images built with nix2container (https://github.com/nlewo/nix2container).
#
# Replaces the per-service Dockerfiles for every image whose contents we can
# express in Nix. Build & load into Docker with:
#
#   nix run .#image-<name>.copyToDockerDaemon
#
# (see the `nix-images` Makefile target). Images not converted (apache,
# frontend, clash, grafana builder) still use their Dockerfiles because they
# are thin layers over third-party base images or node builds.
{
  pkgs,
  lib,
  nix2container,
  # flake packages
  caddy,
  mirrorPkgs ? pkgs.callPackage ./packages.nix { },
}:

let

  ### Layering helper (same pattern as frontend/docker.nix) ###
  # Nest all layers so that prior layers are dependencies of later layers.
  # This way, we should avoid redundant dependencies.
  foldImageLayers =
    let
      mergeToLayer =
        priorLayers: component:
        assert builtins.isList priorLayers;
        assert builtins.isAttrs component;
        let
          layer = nix2container.buildLayer (component // { layers = priorLayers; });
        in
        priorLayers ++ [ layer ];
    in
    layers: lib.foldl mergeToLayer [ ] layers;

  ### Shared helpers ###

  # /bin with bash, coreutils and friends; /usr/bin/env; /bin/sh.
  shellRoot =
    extra:
    pkgs.buildEnv {
      name = "shell-root";
      paths = [
        pkgs.bashInteractive
        pkgs.coreutils
      ]
      ++ extra;
      pathsToLink = [ "/bin" ];
      postBuild = ''
        ln -sfn bash $out/bin/sh
        mkdir -p $out/usr/bin
        ln -s ../../bin/env $out/usr/bin/env
      '';
    };

  # World-writable /tmp. Kept as its own copyToRoot entry with only /tmp in
  # it: perms are attached per source store path, and nix2container refuses
  # to merge a directory (e.g. /var) that appears both with and without
  # perms, so this derivation must not overlap with fakeNss & friends.
  # Other runtime dirs (/run, ...) are created at container runtime on the
  # writable overlay (see git-backend/cmd.sh).
  tmpDirs = pkgs.runCommand "tmp-dirs" { } ''
    mkdir -p $out/tmp
  '';

  tmpPerms = [
    {
      path = tmpDirs;
      regex = "";
      mode = "1777";
    }
  ];

  nsswitch = pkgs.runCommand "nsswitch" { } ''
    mkdir -p $out/etc
    echo "hosts: files dns" > $out/etc/nsswitch.conf
  '';

  caCertificates = pkgs.dockerTools.caCertificates;

  sslEnv = [
    "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
  ];

  buildImage = nix2container.buildImage;
in
{
  ### caddy ###
  caddyImage =
    let
      root = shellRoot [ pkgs.curl ]; # curl: compose healthcheck
    in
    buildImage {
      name = "sjtug/caddy";
      tag = "latest";
      copyToRoot = [
        root
        caCertificates
        nsswitch
        tmpDirs
      ];
      perms = tmpPerms;
      # Isolate the big, stable dependencies into nested layers so image
      # rebuilds only re-push the thin root layer.
      layers = foldImageLayers [
        { deps = [ caddy ]; }
        { deps = [ pkgs.curl ]; }
      ];
      config = {
        Env = sslEnv ++ [
          "PATH=${lib.makeBinPath [ caddy ]}:/bin:/usr/bin"
          "XDG_CONFIG_HOME=/config"
          "XDG_DATA_HOME=/data"
        ];
        WorkingDir = "/srv";
        Cmd = [ "caddy" ];
        ExposedPorts = {
          "80/tcp" = { };
          "443/tcp" = { };
        };
      };
    };

  ### git-backend ###
  gitBackendImage =
    let
      # Runtime environment for nginx + git-http-backend + the pack queue
      # (formerly nix/git-backend-runtime.nix). Everything the container's
      # scripts expect under /runtime/{bin,sbin,conf}.
      gitBackendRuntime = pkgs.buildEnv {
        name = "git-backend-runtime";
        paths = [
          pkgs.fcgiwrap
          pkgs.gitMinimal
          mirrorPkgs.go-queue
          mirrorPkgs.multiwatch
          pkgs.nginx
          pkgs.spawn_fcgi
          pkgs.tini
        ];
      };
      files = pkgs.runCommand "git-backend-files" { } ''
        mkdir -p $out/etc/nginx $out/www/empty
        ln -s ${gitBackendRuntime} $out/runtime
        cp ${../git-backend/nginx.conf} $out/etc/nginx/nginx.conf
        cp ${../git-backend/gitconfig} $out/etc/gitconfig
        install -m 0755 ${../git-backend/cmd.sh} $out/cmd.sh
        install -m 0755 ${../git-backend/queue-wrapper.sh} $out/queue-wrapper.sh
      '';
      root = shellRoot [ ];
    in
    buildImage {
      name = "sjtug/git-backend";
      tag = "latest";
      copyToRoot = [
        root
        files
        pkgs.dockerTools.fakeNss
        caCertificates
        tmpDirs
      ];
      perms = tmpPerms;
      layers = foldImageLayers [
        { deps = [ gitBackendRuntime ]; }
      ];
      config = {
        Env = [ "PATH=/runtime/bin:/runtime/sbin:/bin:/usr/bin" ];
        Entrypoint = [
          "/runtime/bin/tini"
          "-g"
          "--"
        ];
        Cmd = [ "/cmd.sh" ];
        WorkingDir = "/srv";
        ExposedPorts."80/tcp" = { };
        Volumes."/git" = { };
      };
    };

  ### rsyncd ###
  rsyncdImage =
    let
      root = shellRoot [ pkgs.rsync ];
    in
    buildImage {
      name = "sjtug/rsyncd";
      tag = "latest";
      copyToRoot = [
        root
        pkgs.dockerTools.fakeNss
        tmpDirs
      ];
      perms = tmpPerms;
      layers = foldImageLayers [
        { deps = [ pkgs.rsync ]; }
      ];
      config = {
        Env = [ "PATH=/bin:/usr/bin" ];
        WorkingDir = "/app";
        Cmd = [
          "rsync"
          "--daemon"
          "--no-detach"
        ];
        ExposedPorts."873/tcp" = { };
      };
    };

  ### rsync-gateway ###
  rsyncGatewayImage =
    let
      app = pkgs.runCommand "rsync-gateway-app" { } ''
        mkdir -p $out/app
        for f in ${mirrorPkgs.rsync-sjtug}/*; do
          ln -s "$f" $out/app/
        done
      '';
    in
    buildImage {
      name = "sjtug/rsync-gateway";
      tag = "latest";
      copyToRoot = [
        app
        caCertificates
        nsswitch
        tmpDirs
      ];
      perms = tmpPerms;
      layers = foldImageLayers [
        { deps = [ mirrorPkgs.rsync-sjtug ]; }
      ];
      config = {
        Env = sslEnv;
        WorkingDir = "/app";
        Cmd = [ "/app/rsync-gateway" ];
        ExposedPorts."8000/tcp" = { };
      };
    };

  ### mirror-intel ###
  mirrorIntelImage =
    let
      app = pkgs.runCommand "mirror-intel-app" { } ''
        mkdir -p $out/app
        ln -s ${mirrorPkgs.mirror-intel}/mirror-intel $out/app/mirror-intel
        cp ${../mirror-intel/Rocket.toml} $out/app/Rocket.toml
      '';
    in
    buildImage {
      name = "sjtug/mirror-intel";
      tag = "latest";
      copyToRoot = [
        app
        caCertificates
        nsswitch
        tmpDirs
      ];
      perms = tmpPerms;
      layers = foldImageLayers [
        { deps = [ mirrorPkgs.mirror-intel ]; }
      ];
      config = {
        Env = sslEnv ++ [ "ROCKET_TOML_PATH=/app/Rocket.toml" ];
        WorkingDir = "/app";
        Cmd = [ "/app/mirror-intel" ];
        ExposedPorts."8000/tcp" = { };
      };
    };

  ### clash ###
  # Replaces clash/Dockerfile (dreamacro/clash base + runtime-downloaded
  # Country.mmdb). Upstream clash is discontinued; mihomo (clash-meta) is the
  # maintained, config-compatible successor packaged in nixpkgs.
  clashImage =
    let
      etcClash = pkgs.runCommand "clash-etc" { } ''
        mkdir -p $out/etc/clash
        ln -s ${mirrorPkgs.clash-geoip} $out/etc/clash/Country.mmdb
      '';
    in
    buildImage {
      name = "sjtug/clash";
      tag = "latest";
      copyToRoot = [
        etcClash
        caCertificates
        nsswitch
        tmpDirs
      ];
      perms = tmpPerms;
      layers = foldImageLayers [
        { deps = [ pkgs.mihomo ]; }
        { deps = [ mirrorPkgs.clash-geoip ]; }
      ];
      config = {
        Env = sslEnv;
        Entrypoint = [ (lib.getExe pkgs.mihomo) ];
        Cmd = [
          "-d"
          "/etc/clash"
        ];
        ExposedPorts = {
          "8080/tcp" = { };
          "1080/tcp" = { };
        };
      };
    };

  ### lug ###
  # NOTE: Julia + StorageMirrorServer.jl are intentionally dropped — the only
  # worker using them (zhiyuan `julia`) has been commented out in
  # config.zhiyuan.yaml for a long time, and Pkg installation is impure.
  # Re-add via a julia environment derivation if that worker is revived.
  lugImage =
    let
      pythonEnv = pkgs.python3.withPackages (ps: [ ps.python-dateutil ]);
      workerTools = [
        pkgs.rsync
        pkgs.wget
        pkgs.gitMinimal
        pkgs.jq
        pkgs.curl
        pkgs.unzip
        pkgs.openssl
        pkgs.openssh
        pkgs.gnutar
        pkgs.gzip
        pkgs.xz
        pkgs.gnused
        pkgs.gnugrep
        pkgs.gawk
        pkgs.findutils
        pkgs.diffutils
        pkgs.util-linux # flock
        pkgs.hostname
        pkgs.yq-go
        mirrorPkgs.apt-mirror
      ];
      app = pkgs.runCommand "lug-app" { } ''
        mkdir -p $out/app/v2 $out/app/rsync_sjtug $out/root/.ssh
        ln -s ${lib.getExe mirrorPkgs.lug} $out/app/lug
        ln -s ${mirrorPkgs.mirror-clone}/mirror-clone $out/app/v2/mirror-clone
        for f in ${mirrorPkgs.rsync-sjtug}/*; do
          ln -s "$f" $out/app/rsync_sjtug/
        done
        # ftpsync needs a writable etc/ (debian.sh renders ftpsync.conf there),
        # so copy instead of symlinking; perms below make it writable.
        cp -r ${mirrorPkgs.archvsync} $out/app/archvsync
        chmod -R u+w $out/app/archvsync

        # Seed known_hosts as a fallback cache; rsync_ssh.sh refreshes host
        # keys with ssh-keyscan before each sync (keys rotate over time).
        cp ${../lug/known_hosts} $out/root/.ssh/known_hosts
        cp ${../lug/ssh_config} $out/root/.ssh/config

        # `git config --global credential.helper ...` from the old Dockerfile.
        cat > $out/root/.gitconfig <<'EOF'
        [credential]
        	helper = /worker-script/git-credential-helper.sh
        EOF
      '';
      root = shellRoot workerTools;
    in
    buildImage {
      name = "sjtug/lug";
      tag = "latest";
      copyToRoot = [
        root
        app
        pkgs.dockerTools.fakeNss # includes /etc/nsswitch.conf
        caCertificates
        tmpDirs
      ];
      # perms regexes are matched against the *source* store path, hence the
      # unanchored patterns scoped to the `app` derivation.
      perms = tmpPerms ++ [
        {
          path = app;
          regex = "/app/archvsync";
          mode = "0777";
        }
        {
          path = app;
          regex = "/root";
          mode = "0700";
        }
      ];
      # awscli2 and python bring in the heaviest closures; isolate them (and
      # the other stable tool sets) so routine image rebuilds stay cheap.
      layers = foldImageLayers [
        { deps = [ pkgs.awscli2 ]; }
        { deps = [ pythonEnv ]; }
        { deps = workerTools; }
        {
          deps = [
            mirrorPkgs.lug
            mirrorPkgs.mirror-clone
            mirrorPkgs.rsync-sjtug
            mirrorPkgs.archvsync
          ];
        }
      ];
      config = {
        Env = sslEnv ++ [
          "PATH=${
            lib.makeBinPath [
              pkgs.awscli2
              pythonEnv
            ]
          }:/bin:/usr/bin"
          "HOME=/root"
          "GIT_SSL_CAINFO=/etc/ssl/certs/ca-bundle.crt"
        ];
        WorkingDir = "/app";
        Entrypoint = [ "/app/lug" ];
        ExposedPorts = {
          "8081/tcp" = { };
          "7001/tcp" = { };
        };
      };
    };
}
