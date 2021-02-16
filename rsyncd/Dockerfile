FROM debian:buster

ARG USE_SJTUG

RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/deb.debian.org/http:\/\/mirror.sjtu.edu.cn/g' /etc/apt/sources.list ; fi
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/security.debian.org/http:\/\/mirror.sjtu.edu.cn/g' /etc/apt/sources.list ; fi

WORKDIR /app

RUN apt-get update -y -qq && apt-get install rsync -y -qq

CMD rsync --daemon --no-detach
