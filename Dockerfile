FROM alpine:latest

RUN apk update \
 && apk add git perl perl-dev curl build-base gcc abuild binutils perl-plack \
 && curl -L https://cpanmin.us | perl - --sudo App::cpanminus --no-wget \
 && cpanm --no-wget JSON::XS URL::Encode::XS \
 && cpanm --no-wget Dancer2 \
 && apk del perl-dev curl build-base gcc abuild binutils

RUN git clone https://github.com/m4ddav3/moth-api.git
# Alternatively, if the repo is already checked out this might work
# ADD . moth-api/

EXPOSE 3000

WORKDIR moth-api
CMD ["perl", "moth-api.pl"]
