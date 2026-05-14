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
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      pyproject-nix,
      uv2nix,
      uv2nix_hammer_overrides,
      pyproject-build-systems,
      pre-commit-hooks,
      treefmt-nix,
    }:
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
          buildSystemOverrides = {
            loguru = {
              flit-core = [ ];
            };
          };

          cfg = lib.importTOML ./devshell.toml;

          names = cfg.python.workspaces;

          # Load a uv workspace from a workspace root.
          # Uv2nix treats all uv projects as workspace projects.
          workspaces = lib.foldl' (
            acc: path:
            acc
            // {
              "workspace-${path}" = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./. + "/${path}"; };
            }
          ) { } names;

          python =
            pkgs."python${lib.versions.major cfg.python.version}${lib.versions.minor cfg.python.version}";

          pyprojectOverrides = lib.composeExtensions (uv2nix_hammer_overrides.overrides pkgs) (
            # use uv2nix_hammer_overrides.overrides_debug
            #   to see which versions were matched to which overrides
            #  use uv2nix_hammer_overrides.overrides_strict / overrides_strict_debug
            #  to use only overrides exactly matching your python package versions

            # Build system dependencies specified in the shape expected by resolveBuildSystem
            # The empty lists below are lists of optional dependencies.
            #
            # A package `foo` with specification written as:
            # `setuptools-scm[toml]` in pyproject.toml would be written as
            # `foo.setuptools-scm = [ "toml" ]` in Nix
            final: prev:
            let
              inherit (final) resolveBuildSystem;
              inherit (builtins) mapAttrs;
              inherit buildSystemOverrides;
            in
            mapAttrs (
              name: spec:
              prev.${name}.overrideAttrs (old: {
                nativeBuildInputs = old.nativeBuildInputs ++ resolveBuildSystem spec;
              })
            ) buildSystemOverrides
          );

          # Construct package set
          pythonSet' = lib.foldl' (
            acc: path:
            acc
            // {
              "${path}" =
                # Use base package set from pyproject.nix builders
                (pkgs.callPackage pyproject-nix.build.packages {
                  inherit python;
                }).overrideScope
                  (
                    lib.composeManyExtensions [
                      pyproject-build-systems.overlays.default
                      (workspaces."workspace-${path}".mkPyprojectOverlay {
                        # Prefer prebuilt binary wheels as a package source.
                        # Sdists are less likely to "just work" because of the metadata missing from uv.lock.
                        # Binary wheels are more likely to, but may still require overrides for library dependencies.
                        sourcePreference = "wheel";
                      })
                      pyprojectOverrides
                    ]
                  );
            }
          ) { } names;

          editablePythonSet = lib.foldl' (
            acc: path:
            acc
            // {
              "${path}" = pythonSet'.${path}.overrideScope (
                lib.composeExtensions
                  (workspaces."workspace-${path}".mkEditablePyprojectOverlay {
                    root = "$REPO_ROOT";
                  })
                  (
                    _final: prev: {
                      "${path}" = prev.${path}.overrideAttrs (old: {
                        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                          _final.editables
                        ];
                      });
                    }
                  )
              );
            }
          ) { } names;
          virtualenv-dev =
            name:
            editablePythonSet.${name}.mkVirtualEnv "${name}-dev-env" workspaces."workspace-${name}".deps.all;

          pythonSet = lib.foldl' (
            acc: path:
            acc
            // {
              "${path}" = pythonSet'.${path}.pythonPkgsHostHost.overrideScope pyprojectOverrides;
            }
          ) { } names;
          virtualenv =
            name: pythonSet.${name}.mkVirtualEnv "${name}-env" workspaces."workspace-${name}".deps.default;

          inherit (pkgs.callPackages pyproject-nix.build.util { }) mkApplication;

        in
        {
          # https://flake.parts/options/treefmt-nix.html
          # Example: https://github.com/nix-community/buildbot-nix/blob/main/nix/treefmt/flake-module.nix
          treefmt = {
            projectRootFile = ".git/config";
            flakeCheck = cfg.treefmt.flake-check;
            settings.global.excludes = [
              "rsync-gateway/config.*.toml"
            ];

            programs = builtins.listToAttrs (
              map (x: {
                name = x;
                value = {
                  enable = true;
                };
              }) cfg.treefmt.programs
            );
          };

          # https://flake.parts/options/git-hooks-nix.html
          # Example: https://github.com/cachix/git-hooks.nix/blob/master/template/flake.nix
          pre-commit.check.enable = cfg.pre-commit.flake-check;
          pre-commit.settings.configPath = ".pre-commit-config.flake.yaml";
          pre-commit.settings.package = pkgs.${cfg.pre-commit.package};
          pre-commit.settings.hooks = builtins.listToAttrs (
            map (x: {
              name = x;
              value = {
                enable = true;
              };
            }) cfg.pre-commit.hooks
          );

          # Create a development shell containing dependencies from `pyproject.toml`
          devShells = {
            default = pkgs.mkShellNoCC {
              inputsFrom = [
                config.treefmt.build.devShell
                # config.pre-commit.devShell
              ];
            };
          }
          // (lib.foldl' (
            acc: name:
            acc
            // {
              "${name}" = pkgs.mkShell {
                nativeBuildInputs = [
                  (virtualenv-dev name)
                  pkgs.uv
                ];

                env = {
                  UV_NO_SYNC = "1";
                  UV_PYTHON = editablePythonSet.${name}.python.interpreter;
                  UV_PYTHON_DOWNLOADS = "never";
                };

                shellHook = ''
                  unset PYTHONPATH
                  export REPO_ROOT=$(git rev-parse --show-toplevel)/${name}
                '';
              };
            }
          ) { } names);

          packages = lib.foldl' (
            acc: name:
            acc
            // {
              "${name}" = virtualenv name;
            }
          ) { } names;

        };
    };
}
