{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # --- Build toolchain pinned for in-tree Python projects (Stage 0) ---
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix_hammer_overrides = {
      url = "github:TyberiusPrime/uv2nix_hammer_overrides";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # --- Build toolchain pinned for SJTUG Rust projects (Stage 1) ---
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nix2container builds the OCI images (Stage 2) and is reused by lug
    # and rsync-sjtug upstream flakes.
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # --- SJTUG service source repositories ---
    lug = {
      url = "git+https://git.a-stable.com/SJTUG/lug.git?ref=refactor";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nix2container.follows = "nix2container";
      inputs.pre-commit-hooks.follows = "pre-commit-hooks";
      inputs.treefmt-nix.follows = "treefmt-nix";
      # TODO: go2nix
    };
    mirror-clone = {
      url = "github:sjtug/mirror-clone";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.crane.follows = "crane";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.pre-commit-hooks.follows = "pre-commit-hooks";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
    mirror-intel = {
      url = "github:sjtug/mirror-intel";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.crane.follows = "crane";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.pre-commit-hooks.follows = "pre-commit-hooks";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
    rsync-sjtug = {
      url = "github:sjtug/rsync-sjtug";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.crane.follows = "crane";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.nix2container.follows = "nix2container";
      inputs.pre-commit-hooks.follows = "pre-commit-hooks";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-parts,
      pyproject-nix,
      uv2nix,
      uv2nix_hammer_overrides,
      pyproject-build-systems,
      ...
    }@inputs:
    let
      mkFlakeResult = flake-parts.lib.mkFlake { inherit inputs; } {
        imports = [
          # inputs.flake-parts.flakeModules.partitions
          inputs.treefmt-nix.flakeModule
          inputs.pre-commit-hooks.flakeModule
        ];

        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];

        perSystem =
          {
            config,
            pkgs,
            lib,
            system,
            ...
          }:
          let
            workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
            workspaceMembers = pyproject.tool.uv.workspace.members;

            pythonVersion = lib.strings.fileContents ./.python-version;
            python = pkgs."python${lib.versions.major pythonVersion}${lib.versions.minor pythonVersion}";
            pyproject = lib.importTOML ./pyproject.toml;

            hacks = pkgs.callPackage pyproject-nix.build.hacks { };

            overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
            pyprojectOverrides = lib.composeExtensions (uv2nix_hammer_overrides.overrides pkgs) (
              final: prev:
              let
                inherit (final) resolveBuildSystem;
                inherit (builtins) mapAttrs;
                buildSystemOverrides = {
                  loguru.flit-core = [ ];
                };
              in
              mapAttrs (
                name: spec:
                prev.${name}.overrideAttrs (old: {
                  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ resolveBuildSystem spec;
                })
              ) buildSystemOverrides
            );

            basePythonSet =
              (pkgs.callPackage pyproject-nix.build.packages {
                inherit python;
              }).overrideScope
                (
                  lib.composeManyExtensions [
                    pyproject-build-systems.overlays.default
                    overlay
                    pyprojectOverrides
                  ]
                );

            editablePythonSet = basePythonSet.overrideScope (
              lib.composeExtensions
                (workspace.mkEditablePyprojectOverlay {
                  root = "$REPO_ROOT";
                })
                (
                  final: prev:
                  lib.genAttrs workspaceMembers (
                    name:
                    prev.${name}.overrideAttrs (old: {
                      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                        final.editables
                      ];
                    })
                  )
                )
            );
            virtualenv-dev = editablePythonSet.mkVirtualEnv "${pyproject.project.name or "mirror-docker-unified"}-dev-env" workspace.deps.all;

            pythonSet = basePythonSet.pythonPkgsHostHost.overrideScope pyprojectOverrides;
            virtualenv =
              (pythonSet.mkVirtualEnv "${pyproject.project.name or "mirror-docker-unified"}-env" workspace.deps.default)
              .overrideAttrs
                (old: {
                  venvIgnoreCollisions = [ "*" ];
                });

            # mirror-lib: shared helpers for nix2container image construction
            mirror-lib = import ./nix/lib {
              inherit lib;
              inherit (inputs.nix2container.packages.${system}) nix2container;
            };

            caddy = pkgs.callPackage ./nix/package/caddy.nix { };

            mihomo = pkgs.mihomo;

            geoip-metadb = pkgs.fetchurl {
              url = "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/462e21e38eab5adc0027f8486b680e4f61c39efc/geoip.metadb";
              hash = "sha256-N4ng+XWEOSOdzIGqYmtATNc7rtp8FoHO3UMomZsRAHU=";
            };

            geosite-dat = pkgs.fetchurl {
              url = "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/462e21e38eab5adc0027f8486b680e4f61c39efc/geosite.dat";
              hash = "sha256-hYEFCbPJ2dpeKPZYh+iXKXdVGpHIVLgrb4tqgoMRt+o=";
            };

            geoip-dat = pkgs.fetchurl {
              url = "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/462e21e38eab5adc0027f8486b680e4f61c39efc/geoip.dat";
              hash = "sha256-5VG2bpMAqY7MlKXcjIajlzv3AzE4sPph6wY4QZzlAFc=";
            };
          in
          {
            _module.args.pkgs = import nixpkgs {
              inherit system;
              overlays = [
                (_final: _prev: {
                  inherit mirror-lib;
                  inherit (inputs.nix2container.packages.${system}) nix2container;
                })
              ];
            };

            treefmt = {
              projectRootFile = ".git/config";
              settings.global.excludes = [
                "caddy/Caddyfile.*"
                "rsync-gateway/config.*.toml"
              ];

              programs = {
                autocorrect.enable = true;
                dockerfmt.enable = true;
                nixfmt.enable = true;
                prettier.enable = true;
                ruff-check.enable = true;
                ruff-format.enable = true;
                taplo.enable = true;
                zizmor.enable = true;
              };
            };

            pre-commit.settings = {
              package = pkgs.prek;
              configPath = ".pre-commit-config.flake.yaml";
              hooks = {
                treefmt.enable = true;
                caddy-gen-check = {
                  enable = true;
                  name = "Caddyfiles up-to-date";
                  entry = "${virtualenv}/bin/python3 caddy-gen/src/caddy-gen.py -i ./. -o ./caddy --site siyuan,zhiyuan --fail-on-change";
                  language = "system";
                  pass_filenames = false;
                  files = "^(config\\.(siyuan|zhiyuan)\\.yaml|caddy-gen/src/|caddy/Caddyfile\\..*)";
                };
                gateway-gen-check = {
                  enable = true;
                  name = "Gateway configuration up-to-date";
                  entry = "${virtualenv}/bin/python3 gateway-gen/src/gateway-gen.py -i ./. -o ./rsync-gateway --site siyuan,zhiyuan --fail-on-change";
                  language = "system";
                  pass_filenames = false;
                  files = "^(config\\.(siyuan|zhiyuan)\\.yaml|gateway-gen/src/|rsync-gateway/config\\.(siyuan|zhiyuan)\\.toml)";
                };
              };
            };

            devShells.default = pkgs.mkShellNoCC {
              inputsFrom = [
                config.treefmt.build.devShell
                config.pre-commit.devShell
              ];

              packages = [
                pkgs.uv
                virtualenv-dev
              ];

              env = {
                UV_NO_SYNC = "1";
                UV_PYTHON = editablePythonSet.python.interpreter;
                UV_PYTHON_DOWNLOADS = "never";
              };

              shellHook =
                # Bash
                ''
                  unset PYTHONPATH
                  export REPO_ROOT=$(git rev-parse --show-toplevel)
                '';
            };

            packages = {
              inherit virtualenv virtualenv-dev;

              # Raw binaries from flake inputs (for standalone nix build .#<name>)
              inherit (inputs.lug.packages.${system}) lug;
              mirror-clone = inputs.mirror-clone.packages.${system}.default;
              mirror-intel = inputs.mirror-intel.packages.${system}.default;
              inherit (inputs.rsync-sjtug.packages.${system}) rsync-fetcher rsync-gateway rsync-gc;

              # --- nix2container OCI images ---
              docker-image-lug = pkgs.callPackage ./lug/docker.nix {
                inherit (config.packages) lug;
              };

              docker-image-mirror-intel = pkgs.callPackage ./mirror-intel/docker.nix {
                inherit (config.packages) mirror-intel;
              };

              docker-image-rsync-gateway = pkgs.callPackage ./rsync-gateway/docker.nix {
                inherit (config.packages) rsync-gateway;
              };

              docker-image-caddy = pkgs.callPackage ./caddy/docker.nix {
                inherit caddy;
              };

              docker-image-clash = pkgs.callPackage ./clash/docker.nix {
                inherit
                  mihomo
                  geoip-metadb
                  geosite-dat
                  geoip-dat
                  ;
              };

              docker-image-apache = pkgs.callPackage ./apache/docker.nix { };

              docker-image-git-backend = pkgs.callPackage ./git-backend/docker.nix { };

              docker-image-rsyncd = pkgs.callPackage ./rsyncd/docker.nix { };
            };
          };
      };
    in
    mkFlakeResult
    // {
      # Top-level lib: a function consumers call with { lib, nix2container }
      # to get image-building helpers like foldImageLayers.
      #
      #   inputs.mirror-docker-unified.lib {
      #     lib = nixpkgs.lib;
      #     nix2container = inputs.nix2container.packages.${system}.nix2container;
      #   }
      lib = import ./nix/lib;
    };
}
