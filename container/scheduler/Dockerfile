FROM alpine:3.11

RUN apk add --no-cache 'ruby-dev' \
	'g++' 'gcc' 'make' 'git' 'cpio' 'bash' 

RUN umask 002 &&\
    gem install rest-client && \
    gem install activesupport && \
    gem install git && \
    gem install json && \
    gem install yaml


RUN mkdir /usr/share/scheduler

# should build with: crystal build src/scheduler.cr --static 
COPY scheduler /usr/share/scheduler

COPY create-job-cpio.sh /usr/share/scheduler

RUN chown -R 1090:1090 /usr/share/scheduler

EXPOSE 3000

WORKDIR /usr/share/scheduler

