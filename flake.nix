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
        in
        {
          treefmt = {
            projectRootFile = ".git/config";
            settings.global.excludes = [
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
          };
        };
    };
}
