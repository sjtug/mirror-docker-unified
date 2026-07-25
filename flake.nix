{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
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
    go2nix = {
      url = "github:numtide/go2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
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
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
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
          ### Go ###
          goVersion = lib.versions.majorMinor (lib.fileContents ./.go-version);

          # go2nix experimental mode (no plugin):
          #   extra-experimental-features = recursive-nix ca-derivations dynamic-derivations
          goEnv = inputs.go2nix.lib.mkGoEnv {
            inherit (pkgs) go go2nix callPackage;
            nixPackage = pkgs.nixVersions.nix_2_34;
          };

          ### Python ###

          workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
          workspaceMembers = pyproject.tool.uv.workspace.members;

          pythonVersion = lib.strings.fileContents ./.python-version;
          pyproject = lib.importTOML ./pyproject.toml;

          # hacks = pkgs.callPackage pyproject-nix.build.hacks { };

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
              inherit (pkgs) python;
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

          # pythonSet = basePythonSet.pythonPkgsHostHost.overrideScope pyprojectOverrides;
          # virtualenv =
          #   (pythonSet.mkVirtualEnv "${pyproject.project.name or "mirror-docker-unified"}-env" workspace.deps.default)
          #   .overrideAttrs
          #     (old: {
          #       venvIgnoreCollisions = [ "*" ];
          #     });
        in
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [
              (_final: prev: {
                go = prev."go_${lib.replaceString "." "_" goVersion}";
                inherit goEnv;
                inherit (inputs.go2nix.packages.${system}) go2nix;
              })
              (_final: _prev: rec {
                python = pkgs."python${lib.versions.major pythonVersion}${lib.versions.minor pythonVersion}";
                python3 = python;
              })
            ];
          };

          treefmt = {
            projectRootFile = ".git/config";
            settings.global.excludes = [
              "git-backend/go2nix.toml"
              "rsync-gateway/config.*.toml"
            ];

            programs = {
              autocorrect.enable = true;
              dockerfmt.enable = true;
              gofumpt.enable = true;
              goimports.enable = true;
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
              caddy-verify-config-siyuan = {
                enable = true;
                name = "Caddyfile.siyuan validated by Caddy server";
                entry = "${lib.getExe config.packages.caddy} validate --adapter caddyfile --config caddy/Caddyfile.siyuan";
                language = "system";
                pass_filenames = false;
                files = "^(caddy/Caddyfile\\.(siyuan|zhiyuan))$";
              };
              caddy-verify-config-zhiyuan = {
                enable = true;
                name = "Caddyfile.zhiyuan validated by Caddy server";
                entry = "${lib.getExe config.packages.caddy} validate --adapter caddyfile --config caddy/Caddyfile.zhiyuan";
                language = "system";
                pass_filenames = false;
                files = "^(caddy/Caddyfile\\.(siyuan|zhiyuan))$";
              };
              caddy-gen = {
                enable = true;
                name = "Caddyfiles up-to-date";
                entry = "${virtualenv-dev}/bin/python3 caddy-gen/src/caddy-gen.py -i ./. -o ./caddy --site siyuan,zhiyuan --fail-on-change";
                language = "system";
                pass_filenames = false;
                files = "^(config\\.(siyuan|zhiyuan)\\.yaml|caddy-gen/src/)";
              };
              caddy-gen-local = {
                enable = true;
                name = "Caddyfile.local up-to-date";
                entry = "${virtualenv-dev}/bin/python3 caddy-gen/src/caddy-gen.py -i ./lug -o ./caddy --site local --fail-on-change";
                language = "system";
                pass_filenames = false;
                files = "^(lug/config\\.local\\.yaml|caddy-gen/src/)";
              };
              gateway-gen = {
                enable = true;
                name = "Gateway configuration up-to-date";
                entry = "${virtualenv-dev}/bin/python3 gateway-gen/src/gateway-gen.py -i ./. -o ./rsync-gateway --site siyuan,zhiyuan --fail-on-change";
                language = "system";
                pass_filenames = false;
                files = "^(config\\.(siyuan|zhiyuan)\\.yaml|gateway-gen/src/)";
              };
              go2nix = {
                enable = true;
                name = "go2nix";
                description = "Regenerate go2nix.toml lockfile";
                entry =
                  let
                    script = pkgs.writeShellScript "go2nix-wrapper" ''
                      exec ${
                        lib.getExe inputs.go2nix.packages.${system}.go2nix
                      } generate -o git-backend/go2nix.toml git-backend
                    '';
                  in
                  toString script;
                files = "^git-backend/(go2nix\\.toml|go\\.(mod|sum))";
                pass_filenames = false;
              };
            };
          };

          devShells.default = pkgs.mkShellNoCC {
            inputsFrom = [
              config.treefmt.build.devShell
              config.pre-commit.devShell
            ];

            strictDeps = true;

            nativeBuildInputs = [
              pkgs.uv
              virtualenv-dev

              pkgs.go
              pkgs.go2nix

              pkgs.nix-fast-build
            ];

            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON = editablePythonSet.python.interpreter;
              UV_PYTHON_DOWNLOADS = "never";
            };

            shellHook = ''
              unset PYTHONPATH
              export REPO_ROOT=$(git rev-parse --show-toplevel)
            '';
          };

          packages = {
            inherit virtualenv-dev;
            caddy = pkgs.caddy.withPlugins {
              plugins = [
                "github.com/caddyserver/transform-encoder@v0.0.0-20260423033309-ba4124974830"
                "github.com/sjtug/cerberus@v0.4.8"
              ];
              hash = "sha256-pShS64ckH4eVKXJvgDCuDPSrWZb9L8RYjeTqoupRGZE=";
            };
            go-queue = pkgs.callPackage ./git-backend/go-queue.nix { };
            git-backend-runtime = pkgs.callPackage ./git-backend/runtime.nix {
              goQueue = config.packages.go-queue;
              multiwatch = pkgs.callPackage ./git-backend/multiwatch.nix { };
            };
          };
        };
    };
}
