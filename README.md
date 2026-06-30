# mirror-docker-unified

Dockerfile for the all SJTUG mirror servers.

## Docs

![New Architecture](docs/images/new-arch.png)

For more information, refer to our [Wiki](https://github.com/sjtug/mirror-docker-unified/wiki).

## Project structure & maintenance

```sh
.
├── apache # apache dockerfile
├── caddy
├── caddy-gen # caddy configuration generator (for ./caddy)
├── clash # clash dockerfile (for secured connection with monitor node)
├── common # common network configuration
├── data # caddy & lug backend dist
├── docs # Documentation
├── frontend # lug frontend (Next.js)
├── gateway-gen # rsync-sjtug configuration generator (for ./rsync-gateway)
├── git-backend # git backend
├── integration-test # test
├── lug # lug backend dockerfile
├── mirror-intel # mirror-intel configuration
├── rsync-gateway
├── rsyncd
├── scripts
├── secrets
└── upstream
```

Development shell configuration is controlled by `flake.nix`.

See <https://nixos.org/download/> for Nix installation manual.

## Building services from source

`lug`, `mirror-clone`, `mirror-intel`, and the three `rsync-sjtug` binaries (`rsync-gateway`, `rsync-fetcher`, `rsync-gc`) are built from their upstream source repositories through flake inputs, replacing the Dockerfile step that previously fetched GitHub release tarballs:

```sh
nix build .#lug
nix build .#mirror-clone
nix build .#mirror-intel
nix build .#rsync-gateway
nix build .#rsync-fetcher
nix build .#rsync-gc
```

Container images built with nix2container will follow in Stage 2.

## License

Apache 2.0
