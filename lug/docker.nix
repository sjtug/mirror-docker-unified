{
  lib,
  nix2container,
  mirror-lib,
  dockerTools,
  runCommand,
  fetchgit,
  fetchurl,
  symlinkJoin,
  patch,
  # Runtime tools required by worker scripts
  bash,
  rsync,
  wget,
  git,
  coreutils,
  findutils,
  gnugrep,
  gawk,
  gnused,
  curl,
  jq,
  unzip,
  openssl,
  yq-go,
  awscli,
  openssh,
  python3Packages,
  lug,
}:
let
  inherit (mirror-lib) foldImageLayers;

  python = python3Packages.python.withPackages (ps: [
    ps.python-dateutil
  ]);

  archvsync-src = fetchgit {
    url = "https://salsa.debian.org/mirror-team/archvsync.git";
    rev = "57af581ff28a452f053f40639721bb279e1f2cdb";
    hash = "sha256-CMvgMowTqRqYi+Sui5ahDYcBOmfynTVyufoIO8anSuU=";
  };

  archvsync = runCommand "archvsync" { } ''
    cp -R ${archvsync-src} $out
    chmod -R u+w $out
    patch -d $out -p1 < ${./build-script/misc/ftpsync.patch}
  '';

  apt-mirror-src = fetchurl {
    url = "https://raw.githubusercontent.com/apt-mirror/apt-mirror/088fa51357602ed4cea263b8eeff5c5365fcac63/apt-mirror";
    hash = "sha256-DQCQ1/EWyyUHTTij5k88YbxAejSmkT/vKtTgaqlFlAc=";
  };

  apt-mirror-patched = runCommand "apt-mirror-patched" { nativeBuildInputs = [ patch ]; } ''
    mkdir -p $out/bin
    cp ${apt-mirror-src} $out/bin/apt-mirror
    chmod u+w $out/bin/apt-mirror
    patch -d $out/bin -p0 < ${./build-script/misc/apt-mirror-icon2x.patch}
    chmod +x $out/bin/apt-mirror
  '';

  runtimeTools = symlinkJoin {
    name = "lug-runtime-tools";
    paths = [
      bash
      rsync
      wget
      git
      coreutils
      findutils
      gnugrep
      gawk
      gnused
      curl
      jq
      unzip
      openssl
      yq-go
      apt-mirror-patched
      awscli
      openssh
      python
    ];
  };

  rootfs = runCommand "lug-rootfs" { } ''
    mkdir -p $out/bin $out/usr/bin $out/root/.ssh
    ln -s ${bash}/bin/bash $out/bin/bash
    ln -s ${bash}/bin/sh $out/bin/sh
    ln -s ${runtimeTools}/bin/env $out/usr/bin/env
    install -Dm0644 ${./ssh_config} $out/root/.ssh/config
    cat > $out/root/.ssh/known_hosts <<'EOF'
    cran.r-project.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKiGtygea2U3m3a2xg1DekCK9iLuP3o8xeW20seefhTU
    cran.r-project.org ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDETqbL2mXlGsz8FX3yKPDU1pqtN9d3bcapIm+o/qlSUEGiCOsOu7rCK3aqAKa9yugiUbFPp46HlbC0u5UXPzyjwpwzVw+JSTyzALeya5Njnl5mkx3aU24ijbZ1D2VErI+T71fQqqKopaMpNEdzoZ6+VUAscO1B1jnPJzTcejoRuRQ/JY2a1q0C7M0M7X4Trd2+uHeQNeTK1S/dE6MtCo4zTbPNs/lypx74vjjSnR0+NQUympBm2lN0+JnRRIZmWnvgt0mzjwn+bm/TyMEQLn6aGEctzZyE0kJGmhKmDDOUbOaGCGR8YGlHrNRxB0HxAXrUnMWg33F52iikCMpibsnnNzrZ9t767mq/G14l3psdnSVHNG5nHlXE7ruCVfEYEM2py7Yp6O8He5x5sft81YWvLB3qMc5tnE4fbsx+Hzc6A3mVpLOyoxjB8n0COuHm/54iKESHUEsRPtqDMpezWnuW5IFB/VhtoNzeBkr0/Puor1ZPBeM8SjRIDJ1Ju5Dt5Tc=
    EOF
    cat > $out/root/.gitconfig <<'EOF'
    [credential]
      helper = /worker-script/git-credential-helper.sh
    [pack]
      threads = 4
      windowMemory = 512m
    [core]
      compression = 1
      bare = true
    [uploadpack]
      allowReachableSHA1InWant = true
    EOF
  '';
in
nix2container.buildImage {
  name = "lug";
  tag = "latest";

  copyToRoot = [
    dockerTools.caCertificates
    rootfs
  ];

  layers = foldImageLayers [
    # Runtime tools needed by worker scripts on PATH
    {
      deps = [
        runtimeTools
      ];
    }
    # The lug daemon and lugctl
    { deps = [ lug ]; }
  ];

  config = {
    Entrypoint = [ (lib.getExe' lug "lug") ];
    Cmd = [
      "-c"
      "/config.yaml"
    ];
    ExposedPorts = {
      "7001/tcp" = { };
      "8081/tcp" = { };
    };
    Env = [
      "PATH=${runtimeTools}/bin:/usr/local/bin:/usr/bin:/bin"
      "ARCHVSYNC_DIR=${archvsync}"
      "GIT_CONFIG_GLOBAL=/root/.gitconfig"
    ];
  };
}
