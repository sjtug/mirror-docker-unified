FROM debian:buster

ARG USE_SJTUG
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/deb.debian.org/http:\/\/mirrors.sjtug.sjtu.edu.cn/g' /etc/apt/sources.list ; fi

WORKDIR /app
RUN apt-get update && apt-get install rsync wget git jq curl unzip -y
RUN apt-get install apt-transport-https ca-certificates -y
RUN wget -qO- -O tmp.zip https://github.com/sjtug/lug/releases/download/0.12.2/lug.zip && unzip tmp.zip && rm tmp.zip && chmod +x ./lug
RUN wget -qO- -O tmp.tar.gz https://github.com/sjtug/mirror-clone/releases/download/v0.1.0/mirror-clone.tar.gz && tar -xvf tmp.tar.gz && rm tmp.tar.gz

ENTRYPOINT ["./lug"]
