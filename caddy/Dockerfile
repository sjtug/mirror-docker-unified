FROM caddy:2.1.1

ARG USE_SJTUG
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/dl-cdn.alpinelinux.org/http:\/\/mirrors.sjtug.sjtu.edu.cn/g' /etc/apk/repositories ; fi
RUN apk update && apk add curl

CMD caddy
