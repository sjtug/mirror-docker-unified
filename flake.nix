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
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
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
          inherit (inputs)
            pyproject-build-systems
            pyproject-nix
            uv2nix
            uv2nix_hammer_overrides
            ;

          cfg = lib.importTOML ./devshell.toml;
          workspaceNames = cfg.python.workspaces;

          buildSystemOverrides = {
            loguru.flit-core = [ ];
          };

          enableAll =
            names:
            lib.genAttrs names (_: {
              enable = true;
            });

          workspaces = lib.genAttrs workspaceNames (
            name: uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./. + "/${name}"; }
          );

          python =
            pkgs."python${lib.versions.major cfg.python.version}${lib.versions.minor cfg.python.version}";

          pyprojectOverrides = lib.composeExtensions (uv2nix_hammer_overrides.overrides pkgs) (
            final: prev:
            lib.mapAttrs (
              name: spec:
              prev.${name}.overrideAttrs (old: {
                nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ final.resolveBuildSystem spec;
              })
            ) buildSystemOverrides
          );

          basePythonSet = pkgs.callPackage pyproject-nix.build.packages {
            inherit python;
          };

          pythonSets = lib.genAttrs workspaceNames (
            name:
            basePythonSet.overrideScope (
              lib.composeManyExtensions [
                pyproject-build-systems.overlays.default
                (workspaces.${name}.mkPyprojectOverlay {
                  sourcePreference = "wheel";
                })
                pyprojectOverrides
              ]
            )
          );

          editablePythonSets = lib.genAttrs workspaceNames (
            name:
            pythonSets.${name}.overrideScope (
              lib.composeExtensions
                (workspaces.${name}.mkEditablePyprojectOverlay {
                  root = "$REPO_ROOT";
                })
                (
                  final: prev: {
                    "${name}" = prev.${name}.overrideAttrs (old: {
                      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                        final.editables
                      ];
                    });
                  }
                )
            )
          );

          runtimePythonSets = lib.genAttrs workspaceNames (
            name: pythonSets.${name}.pythonPkgsHostHost.overrideScope pyprojectOverrides
          );

          mkDevVirtualenv =
            name: editablePythonSets.${name}.mkVirtualEnv "${name}-dev-env" workspaces.${name}.deps.all;

          mkVirtualenv =
            name: runtimePythonSets.${name}.mkVirtualEnv "${name}-env" workspaces.${name}.deps.default;

          mkWorkspaceShell =
            name:
            pkgs.mkShell {
              nativeBuildInputs = [
                (mkDevVirtualenv name)
                pkgs.uv
              ];

              env = {
                UV_NO_SYNC = "1";
                UV_PYTHON = editablePythonSets.${name}.python.interpreter;
                UV_PYTHON_DOWNLOADS = "never";
              };

              shellHook = ''
                unset PYTHONPATH
                export REPO_ROOT=$(git rev-parse --show-toplevel)/${name}
              '';
            };
        in
        {
          treefmt = {
            projectRootFile = ".git/config";
            flakeCheck = cfg.treefmt.flake-check;
            settings.global.excludes = [
              "rsync-gateway/config.*.toml"
            ];

            programs = enableAll cfg.treefmt.programs;
          };

          pre-commit = {
            check.enable = cfg.pre-commit.flake-check;
            settings = {
              configPath = ".pre-commit-config.flake.yaml";
              package = pkgs.${cfg.pre-commit.package};
              hooks = enableAll cfg.pre-commit.hooks;
            };
          };

          devShells = {
            default = pkgs.mkShellNoCC {
              inputsFrom = [
                config.treefmt.build.devShell
              ];
            };
          }
          // lib.genAttrs workspaceNames mkWorkspaceShell;

          packages = lib.genAttrs workspaceNames mkVirtualenv;
        };
    };
}
