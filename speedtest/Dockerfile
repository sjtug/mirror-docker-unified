FROM debian:buster

ARG USE_SJTUG

RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/deb.debian.org/http:\/\/mirror.sjtu.edu.cn/g' /etc/apt/sources.list ; fi
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/security.debian.org/http:\/\/mirror.sjtu.edu.cn/g' /etc/apt/sources.list ; fi

WORKDIR /app

RUN apt-get update -y -qq && apt-get install wget curl -y -qq

ARG SPEEDTEST_URL

RUN if [ "$USE_SJTUG" = true ] ; then \
        wget -O tmp.tar.gz https://mirror.sjtu.edu.cn/github-release/librespeed/speedtest-go/releases/download/${SPEEDTEST_URL} || \
        wget -O tmp.tar.gz https://s3.jcloud.sjtu.edu.cn/899a892efef34b1b944a19981040f55b-oss01/github-release/librespeed/speedtest-go/releases/download/${SPEEDTEST_URL} || \
        wget -O tmp.tar.gz https://github.com/librespeed/speedtest-go/releases/download/${SPEEDTEST_URL} ; \
    else \
        timeout 5 curl -v -I https://mirror.sjtu.edu.cn/github-release/librespeed/speedtest-go/releases/download/${SPEEDTEST_URL} ; \
        wget -O tmp.tar.gz https://github.com/librespeed/speedtest-go/releases/download/${SPEEDTEST_URL} ; \
    fi && tar -xvf tmp.tar.gz && rm tmp.tar.gz

RUN rm -rf /app/assets/*.html
COPY ./index.html /app/assets
COPY ./settings.toml /app/settings.toml

CMD ./speedtest-backend
