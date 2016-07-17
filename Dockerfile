FROM alpine:latest

RUN apk update && apk add git perl perl-dev curl build-base gcc abuild binutils perl-plack
RUN curl -L https://cpanmin.us | perl - --sudo App::cpanminus --no-wget
RUN cpanm --no-wget JSON::XS URL::Encode::XS && cpanm --no-wget Dancer2
RUN apk del perl-dev curl build-base gcc abuild binutils

RUN git clone https://github.com/m4ddav3/moth-api.git

EXPOSE 3000

WORKDIR moth-api
CMD ["perl", "moth-api.pl"]

#CMD ["/bin/sh"]
#RUN top
#RUN ash

# install perl, git
# curl -L https://cpanmin.us | perl - App::cpanminus
# install carton, dancer2, json
# clone repo
# run moth-api
# expose 3000



# apk add build-base gcc abuild binutils binutils-doc gcc-doc perl-plack
# cpanm JSON::XS URL::Encode::XS Dancer2
