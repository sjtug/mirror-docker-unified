{
  lib,
  goEnv,
  symlinkJoin,
}:

let
  pname = "go-queue";
  version = "0-unstable-2026-07-24";
  goAppDrv = goEnv.buildGoApplicationExperimental {
    inherit pname version;

    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./go-queue.go
        ./go-queue_test.go
        ./go.mod
        ./go.sum
      ];
    };

    goLock = ./go2nix.toml;

    subPackages = [ "." ];

    CGO_ENABLED = 0;

    ldflags = [
      "-s"
      "-w"
    ];

    meta = {
      description = "Admission controller for Git pack generation";
      mainProgram = "go-queue";
    };
  };
in
symlinkJoin {
  name = "${pname}-${version}";
  paths = [ goAppDrv.target ];
}
