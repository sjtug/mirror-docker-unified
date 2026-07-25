FROM nixos/nix:2.35.1

WORKDIR /build
COPY --from=flake .go-version .python-version flake.nix flake.lock ./
COPY go.mod go.sum go-queue.go go-queue_test.go go-queue.nix go2nix.toml multiwatch.nix runtime.nix ./git-backend/
RUN echo "experimental-features = nix-command flakes recursive-nix ca-derivations dynamic-derivations" >>/etc/nix/nix.conf
RUN nix \
    --option extra-substituters "https://sjtug.cachix.org" \
    --option extra-trusted-public-keys "sjtug.cachix.org-1:0bD3nO47HROvtvVfkodDpE7AUwjFxQ/6l4fCbcC+7bc=" \
    --option filter-syscalls false \
    build .#git-backend-runtime \
    --out-link /runtime \
    && nix-store --gc

ENV PATH=/runtime/bin:/runtime/sbin:${PATH}

# The container listens on port 80, map as needed.
EXPOSE 80

# This is where the repositories will be stored, and should be mounted from
# the host (or a volume container).
VOLUME ["/git"]

COPY nginx.conf /etc/nginx/nginx.conf
COPY gitconfig /etc/gitconfig
COPY cmd.sh /cmd.sh
COPY queue-wrapper.sh /queue-wrapper.sh
RUN chmod 0755 /cmd.sh /queue-wrapper.sh

WORKDIR /srv

ENTRYPOINT ["/runtime/bin/tini", "-g", "--"]
CMD ["/cmd.sh"]
