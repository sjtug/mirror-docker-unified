# Prebuilt upstream releases and patched vendored tools used by the
# container images in nix/containers.nix.
#
# Versions were previously docker-compose build args; they are pinned here
# together with their content hashes.
{
  lib,
  stdenv,
  runCommand,
  fetchurl,
  fetchgit,
  autoPatchelfHook,
  patch,
  perl,
  buildGoModule,
  glib,
  libev,
  meson,
  ninja,
  pkg-config,
  caddy,
}:

let
  versions = {
    mirror-clone = "v0.2.46-2";
    rsync-sjtug = "v0.4.19";
    mirror-intel = "v0.1.46";

    cerberus = "v0.4.9";
    caddy-waf = "v0.4.1-sjtug.3";
  };
in
{
  caddy = caddy.withPlugins {
    plugins = [
      "github.com/sjtug/cerberus@${versions.cerberus}"
      "github.com/fabriziosalmi/caddy-waf=github.com/sjtug/caddy-waf@${versions.caddy-waf}"
    ];
    hash = "sha256-v/QGLYCSVR2A5IoLnwLOyGVPZj2RuW1ZUp0+wcxZSbQ=";
  };

  ### go-queue (admission controller for Git pack generation) ###
  go-queue = buildGoModule {
    pname = "go-queue";
    version = "0-unstable-2026-07-24";

    src = lib.fileset.toSource {
      root = ../git-backend;
      fileset = lib.fileset.unions [
        ../git-backend/go-queue.go
        ../git-backend/go-queue_test.go
        ../git-backend/go.mod
        ../git-backend/go.sum
      ];
    };

    vendorHash = "sha256-FdHYe9fIEyOgt6Cylefx8eMwIAvWCq8IVGFBNHT03aw=";

    subPackages = [ "." ];

    env.CGO_ENABLED = 0;

    ldflags = [
      "-s"
      "-w"
    ];

    meta = {
      description = "Admission controller for Git pack generation";
      mainProgram = "go-queue";
    };
  };

  ### multiwatch (fork and supervise multiple instances of a program) ###
  multiwatch = stdenv.mkDerivation (finalAttrs: {
    pname = "multiwatch";
    version = "1.0.1";

    src = fetchurl {
      url = "https://download.lighttpd.net/multiwatch/releases-1.x/multiwatch-${finalAttrs.version}.tar.xz";
      hash = "sha256-6KaPLIb5njTIas9zJf5tGcgXWTXyUhMUVS3OY74i8WQ=";
    };

    nativeBuildInputs = [
      meson
      ninja
      pkg-config
    ];

    buildInputs = [
      glib
      libev
    ];

    meta = {
      description = "Fork and supervise multiple instances of a program";
      homepage = "https://redmine.lighttpd.net/projects/multiwatch";
      license = lib.licenses.mit;
      mainProgram = "multiwatch";
      platforms = lib.platforms.unix;
    };
  });

  ### rsync-sjtug (static musl binaries: rsync-gateway, rsync-fetcher, rsync-gc) ###
  rsync-sjtug = runCommand "rsync-sjtug-${versions.rsync-sjtug}" { } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://github.com/sjtug/rsync-sjtug/releases/download/${versions.rsync-sjtug}/rsync-sjtug-x86_64-unknown-linux-musl.tar.gz";
        hash = "sha256-JcF5Zue/WTxgbbJ5XA8IH8UxW64D8/qHPZVIheJx4ks=";
      }
    } --strip-components=2 -C $out
  '';

  ### mirror-intel (static musl binary) ###
  mirror-intel = runCommand "mirror-intel-${versions.mirror-intel}" { } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://github.com/sjtug/mirror-intel/releases/download/${versions.mirror-intel}/mirror-intel.tar.gz";
        hash = "sha256-+Mo94Qxzxi5jw+K1WnlMvTSKjMAfe+RlqCgbYjUO4dc=";
      }
    } -C $out
  '';

  ### mirror-clone v2 (static musl binary) ###
  mirror-clone = runCommand "mirror-clone-${versions.mirror-clone}" { } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://github.com/sjtug/mirror-clone/releases/download/${versions.mirror-clone}/mirror-clone.tar.gz";
        hash = "sha256-LgpkYnKeBLZNLaZ/Nd2kHmGj6ZiGXvUpXsb6etHbxtk=";
      }
    } -C $out
  '';

  ### ftpsync (Debian archvsync, patched) ###
  archvsync = stdenv.mkDerivation {
    pname = "archvsync";
    version = "unstable-2018-05-13";
    src = fetchgit {
      url = "https://salsa.debian.org/mirror-team/archvsync.git";
      rev = "57af581ff28a452f053f40639721bb279e1f2cdb";
      hash = "sha256-CMvgMowTqRqYi+Sui5ahDYcBOmfynTVyufoIO8anSuU=";
    };
    patches = [ ../lug/build-script/misc/ftpsync.patch ];
    dontBuild = true;
    installPhase = ''
      mkdir -p $out
      cp -r . $out
    '';
  };

  ### MaxMind GeoIP country database for clash/mihomo (pinned release) ###
  clash-geoip = fetchurl {
    url = "https://github.com/Dreamacro/maxmind-geoip/releases/download/20260812/Country.mmdb";
    hash = "sha256-tqUl2P/XYotZoceFMmSTeuOiNjLe6+2dquLr/7+HYmU=";
  };

  ### apt-mirror (pinned upstream commit, patched) ###
  apt-mirror =
    runCommand "apt-mirror"
      {
        src = fetchurl {
          url = "https://raw.githubusercontent.com/apt-mirror/apt-mirror/088fa51357602ed4cea263b8eeff5c5365fcac63/apt-mirror";
          hash = "sha256-DQCQ1/EWyyUHTTij5k88YbxAejSmkT/vKtTgaqlFlAc=";
        };
        nativeBuildInputs = [ patch ];
      }
      ''
        cp $src apt-mirror
        chmod +w apt-mirror
        patch apt-mirror ${../lug/build-script/misc/apt-mirror-icon2x.patch}
        substituteInPlace apt-mirror --replace-fail '#!/usr/bin/perl' '#!${lib.getExe perl}'
        install -Dm755 apt-mirror $out/bin/apt-mirror
      '';
}
