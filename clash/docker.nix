{
  lib,
  nix2container,
  mirror-lib,
  dockerTools,
  runCommand,
  mihomo,
  geoip-metadb,
  geosite-dat,
  geoip-dat,
}:
let
  inherit (mirror-lib) foldImageLayers;

  rootfs = runCommand "mihomo-rootfs" { } ''
    mkdir -p $out/etc/clash
    ln -s ${geoip-metadb} $out/etc/clash/geoip.metadb
    ln -s ${geosite-dat} $out/etc/clash/geosite.dat
    ln -s ${geoip-dat} $out/etc/clash/geoip.dat
  '';
in
nix2container.buildImage {
  name = "clash";
  tag = "latest";

  copyToRoot = [
    dockerTools.caCertificates
    rootfs
  ];

  layers = foldImageLayers [
    {
      deps = [
        mihomo
        geoip-metadb
        geosite-dat
        geoip-dat
      ];
    }
  ];

  config = {
    Cmd = [
      "${mihomo}/bin/mihomo"
      "-d"
      "/etc/clash"
    ];
    ExposedPorts = {
      "7890/tcp" = { };
      "7891/tcp" = { };
    };
  };
}
