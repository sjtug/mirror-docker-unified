FROM debian:buster

ARG USE_SJTUG
RUN if [ "$USE_SJTUG" = "TRUE" ] ; then sed -i 's/http:\/\/deb.debian.org/http:\/\/mirrors.sjtug.sjtu.edu.cn/g' /etc/apt/sources.list ; fi

WORKDIR /app

RUN apt-get update -y -qq && apt-get install wget -y -qq
RUN wget https://github.com/sjtug/mirror-intel/releases/download/untagged-c6c672ee0cf402269042746cb53dab94eaebcc53/mirror-intel.tar.gz \
    && tar -xvf mirror-intel.tar.gz \
    && rm mirror-intel.tar.gz

COPY Rocket.toml /app

CMD /app/mirror-intel