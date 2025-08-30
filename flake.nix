{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
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
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      flake-parts,
      ...
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
        "x86_64-darwin"
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
          cfg = builtins.fromTOML (builtins.readFile ./devshell.toml);

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

          # Construct package set
          pythonSet = lib.foldl' (
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
                        # sourcePreference = "wheel"; # or sourcePreference = "sdist";
                        sourcePreference = "wheel";
                      })
                    ]
                  );
            }
          ) { } names;
        in
        {
          # https://flake.parts/options/treefmt-nix.html
          # Example: https://github.com/nix-community/buildbot-nix/blob/main/nix/treefmt/flake-module.nix
          treefmt = {
            projectRootFile = "flake.nix";
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
            default = pkgs.mkShell {
              inputsFrom = [
                config.treefmt.build.devShell
                # config.pre-commit.devShell
              ];
              buildInputs = [ pkgs.cachix ];
              shellHook = builtins.concatStringsSep "\n" (
                builtins.map (
                  path: "rm -rf ${path}/.venv && nix build .#pythonEnv-${path} --out-link ${path}/.venv"
                ) names
              );
            };
          };

          # Build `.venv` in Nix derivation
          packages = lib.foldl' (
            acc: path:
            acc
            // {
              "pythonEnv-${path}" =
                pythonSet.${path}.mkVirtualEnv "${path}-env"
                  workspaces."workspace-${path}".deps.all;
            }
          ) { } names;
        };
    };
}
