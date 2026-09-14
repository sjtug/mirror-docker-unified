{
  nixConfig = {
    extra-substituters = [ "https://sjtug.cachix.org" ];
    extra-trusted-public-keys = [ "sjtug.cachix.org-1:0bD3nO47HROvtvVfkodDpE7AUwjFxQ/6l4fCbcC+7bc=" ];
  };
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
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    frontend = {
      url = "github:sjtug/sjtug-mirror-frontend";
      inputs.nix2container.follows = "nix2container";
    };
    lug = {
      # TODO: switch back to master
      url = "github:sjtug/lug/next-gen";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
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
          go = pkgs."go_${lib.replaceString "." "_" goVersion}";

          ### Python ###

          workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
          workspaceMembers = pyproject.tool.uv.workspace.members;

          pythonVersion = lib.strings.fileContents ./.python-version;
          python = pkgs."python${lib.versions.major pythonVersion}${lib.versions.minor pythonVersion}";
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

          caddyValidate =
            caddyfile:
            lib.concatStringsSep " " [
              "${pkgs.coreutils}/bin/env"
              "CADDY_WAF_IP_BLACKLIST_FILE=caddy/waf/crawler-ip-blacklist.txt.example"
              "CADDY_WAF_IP_WHITELIST_FILE=caddy/waf/bandwidth-quota-whitelist.txt.example"
              "CADDY_WAF_DNS_BLACKLIST_FILE=caddy/waf/dns-blacklist.txt.example"
              "CADDY_WAF_LOG_PATH=/tmp/caddy-waf-validation.log"
              "CADDY_BANDWIDTH_QUOTA_WHITELIST_FILE=caddy/waf/bandwidth-quota-whitelist.txt.example"
              "CADDY_BANDWIDTH_QUOTA_DB=/tmp/caddy-bandwidth-quota-validation.db"
              "${lib.getExe config.packages.caddy}"
              "validate --adapter caddyfile --config ${caddyfile}"
            ];

          # pythonSet = basePythonSet.pythonPkgsHostHost.overrideScope pyprojectOverrides;
          # virtualenv =
          #   (pythonSet.mkVirtualEnv "${pyproject.project.name or "mirror-docker-unified"}-env" workspace.deps.default)
          #   .overrideAttrs
          #     (old: {
          #       venvIgnoreCollisions = [ "*" ];
          #     });
        in
        {
          treefmt = {
            projectRootFile = ".git/config";
            settings.global.excludes = [
              "monitor/g-storage/**/*.sops.*"
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
                entry = caddyValidate "caddy/Caddyfile.siyuan";
                language = "system";
                pass_filenames = false;
                files = "^(caddy/(Caddyfile\\.(local|siyuan|zhiyuan)|waf/.*)|flake\\.nix$)";
              };
              caddy-verify-config-zhiyuan = {
                enable = true;
                name = "Caddyfile.zhiyuan validated by Caddy server";
                entry = caddyValidate "caddy/Caddyfile.zhiyuan";
                language = "system";
                pass_filenames = false;
                files = "^(caddy/(Caddyfile\\.(local|siyuan|zhiyuan)|waf/.*)|flake\\.nix$)";
              };
              caddy-verify-config-local = {
                enable = true;
                name = "Caddyfile.local validated by Caddy server";
                entry = caddyValidate "caddy/Caddyfile.local";
                language = "system";
                pass_filenames = false;
                files = "^(caddy/(Caddyfile\\.(local|siyuan|zhiyuan)|waf/.*)|flake\\.nix$)";
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

              go

              pkgs.cachix
              pkgs.jq
              pkgs.nix-fast-build
              pkgs.prometheus-alertmanager
              pkgs.prometheus-blackbox-exporter
              pkgs.prometheus.cli
              pkgs.shellcheck
              pkgs.sops
            ];

            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON = editablePythonSet.python.interpreter;
              UV_PYTHON_DOWNLOADS = "never";
            };

            shellHook = /* Bash */ ''
              unset PYTHONPATH
              export REPO_ROOT=$(git rev-parse --show-toplevel)
            '';
          };

          packages =
            let
              lug = inputs.lug.packages.${system}.default;
              mirrorPkgs = pkgs.callPackage ./nix/packages.nix { };
              containers = import ./nix/containers.nix {
                inherit pkgs lib;
                inherit (inputs.nix2container.packages.${system}) nix2container;
                inherit (config.packages) caddy;
                inherit lug;
                inherit mirrorPkgs;
              };
            in
            {
              inherit virtualenv-dev;

              inherit (mirrorPkgs)
                caddy
                go-queue
                multiwatch
                mirror-clone
                mirror-intel
                rsync-sjtug
                archvsync
                apt-mirror
                ;

              image-caddy = containers.caddyImage;
              image-git-backend = containers.gitBackendImage;
              image-rsyncd = containers.rsyncdImage;
              image-rsync-gateway = containers.rsyncGatewayImage;
              image-mirror-intel = containers.mirrorIntelImage;
              image-clash = containers.clashImage;
            }
            // (
              # Built by the frontend flake's own docker.nix (nix2container).
              # PUBLIC_SITE_NAME is inlined by Astro/Vite at build time, so
              # each site needs its own frontend build; both images share the
              # name mirror-frontend:latest and only one is loaded per host.
              let
                inherit (inputs.frontend.packages.${system}) docker-image frontend;
                frontendImageFor =
                  site:
                  docker-image.override {
                    frontend = frontend.overrideAttrs (oldAttrs: {
                      env = (oldAttrs.env or { }) // {
                        PUBLIC_SITE_NAME = site;
                      };
                    });
                    inherit site;
                  };
              in
              {
                inherit frontend;
                image-frontend-siyuan = frontendImageFor "Siyuan";
                image-frontend-zhiyuan = frontendImageFor "Zhiyuan";
              }
            )
            // {
              inherit lug;
              image-lug = containers.lugImage;
            };
        };
    };
}
