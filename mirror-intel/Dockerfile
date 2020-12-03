FROM debian:buster

ARG USE_SJTUG
RUN if [ "$USE_SJTUG" = "TRUE" ] ; then sed -i 's/http:\/\/deb.debian.org/http:\/\/mirrors.sjtug.sjtu.edu.cn/g' /etc/apt/sources.list ; fi

WORKDIR /app

RUN apt-get update -y -qq && apt-get install wget -y -qq
RUN wget https://github.com/sjtug/mirror-intel/suites/1602727150/artifacts/29249350

COPY Rocket.toml /app

CMD /app/mirror-intel
