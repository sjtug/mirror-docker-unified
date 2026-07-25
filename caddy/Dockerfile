FROM nixos/nix:2.35.1

WORKDIR /build
COPY --from=flake .go-version .python-version flake.nix flake.lock ./
RUN nix \
    --extra-experimental-features "nix-command flakes" \
    --option extra-substituters "https://sjtug.cachix.org" \
    --option extra-trusted-public-keys "sjtug.cachix.org-1:0bD3nO47HROvtvVfkodDpE7AUwjFxQ/6l4fCbcC+7bc=" \
    --option filter-syscalls false \
    build .#caddy \
    --out-link /result \
    && nix-store --gc

ENV PATH=/result/bin:${PATH}
ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data

WORKDIR /srv
CMD ["caddy"]
