{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "go-queue";
  version = "0-unstable-2026-07-24";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go-queue.go
      ./go-queue_test.go
      ./go.mod
      ./go.sum
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
}
