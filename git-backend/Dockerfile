# small is beautiful
FROM debian:trixie-slim

LABEL org.opencontainers.image.authors="Anthony Hogg anthony@hogg.fr"

# The container listens on port 80, map as needed
EXPOSE 80

# This is where the repositories will be stored, and
# should be mounted from the host (or a volume container)
VOLUME ["/git"]

ARG USE_SJTUG

RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/deb.debian.org/http:\/\/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources ; fi
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/security.debian.org/http:\/\/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources ; fi

# Install latest Nginx
# Ref: https://nginx.org/en/linux_packages.html#Debian
RUN apt-get update \
    && apt install -yy curl gnupg2 ca-certificates lsb-release debian-archive-keyring
RUN curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
    | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
RUN mkdir -p ~/.gnupg && chmod 0700 ~/.gnupg
RUN gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg \
    | grep '573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62' \
    || { echo "ERROR: nginx key fingerprint mismatch"; exit 1; }
RUN echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
https://nginx.org/packages/debian $(lsb_release -cs) nginx" \
    | tee /etc/apt/sources.list.d/nginx.list
RUN echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
    | tee /etc/apt/preferences.d/99nginx

# We need the following:
# - git, because that gets us the git-http-backend CGI script
# - fcgiwrap, because that is how nginx does CGI
# - spawn-fcgi, to launch fcgiwrap and to create the unix socket
# - nginx, because it is our frontend
RUN apt-get update \
    && apt-get install -yy nginx git fcgiwrap spawn-fcgi

COPY nginx.conf /etc/nginx/nginx.conf

# launch fcgiwrap via spawn-fcgi; launch nginx in the foreground
# so the container doesn't die on us; supposedly we should be
# using supervisord or something like that instead, but this
# will do
RUN git config --global pack.threads 4 \
    && git config --global pack.windowMemory 512m \
    && git config --global core.compression 1 \
    && git config --global uploadpack.allowReachableSHA1InWant true \
    && git config --global core.bare true


CMD spawn-fcgi -s /run/fcgi.sock /usr/sbin/fcgiwrap && \
    nginx -g "daemon off;"
