FROM caddy:2.7

RUN caddy add-package github.com/caddyserver/transform-encoder

ARG USE_SJTUG
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/https:\/\/dl-cdn.alpinelinux.org/http:\/\/mirrors.ustc.edu.cn/g' /etc/apk/repositories ; fi
RUN apk update && apk add curl

CMD caddy
