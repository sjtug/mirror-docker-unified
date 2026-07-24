FROM golang:1.26-alpine AS queue-builder

WORKDIR /src
COPY go.mod go.sum go-queue.go go-queue_test.go ./
RUN go test ./... \
    && mkdir -p /out \
    && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/go-queue ./go-queue.go

FROM debian:trixie-slim

LABEL org.opencontainers.image.authors="Anthony Hogg anthony@hogg.fr"

# The container listens on port 80, map as needed.
EXPOSE 80

# This is where the repositories will be stored, and should be mounted from
# the host (or a volume container).
VOLUME ["/git"]

ARG USE_SJTUG

RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/deb.debian.org/http:\/\/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources ; fi
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/security.debian.org/http:\/\/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources ; fi

# Install latest Nginx.
# Ref: https://nginx.org/en/linux_packages.html#Debian
RUN apt-get update \
    && apt-get install -yy curl gnupg2 ca-certificates lsb-release debian-archive-keyring
RUN curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
    | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
RUN mkdir -p ~/.gnupg && chmod 0700 ~/.gnupg
RUN gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg \
    | grep '573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62' \
    || { echo "ERROR: nginx key fingerprint mismatch"; exit 1; }
RUN echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
https://nginx.org/packages/debian $(lsb_release -cs) nginx" \
    | tee /etc/apt/sources.list.d/nginx.list
RUN printf "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
    | tee /etc/apt/preferences.d/99nginx

# git provides git-http-backend. fcgiwrap and spawn-fcgi bridge it to Nginx;
# multiwatch keeps the FastCGI worker pool in the foreground; tini provides
# correct PID 1 signal forwarding and child reaping.
RUN apt-get update \
    && apt-get install -yy --no-install-recommends nginx git fcgiwrap spawn-fcgi multiwatch tini \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY nginx.conf /etc/nginx/nginx.conf
COPY gitconfig /etc/gitconfig
COPY --from=queue-builder /out/go-queue /usr/local/bin/go-queue
COPY cmd.sh /cmd.sh
COPY queue-wrapper.sh /queue-wrapper.sh
RUN chmod 0755 /cmd.sh /queue-wrapper.sh /usr/local/bin/go-queue

ENTRYPOINT ["tini", "-g", "--"]
CMD ["/cmd.sh"]
