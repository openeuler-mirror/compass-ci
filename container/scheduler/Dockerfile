FROM alpine:3.11

RUN apk add --no-cache 'ruby-dev' \
	'g++' 'gcc' 'make' 'git' 'cpio' 'bash' 

RUN gem install rest-client && \
    gem install activesupport && \
    gem install git && \
    gem install json && \
    gem install yaml


RUN mkdir /usr/share/scheduler

# run in docker, localhost should set to host docker0 ip
# run@host: ip addr show docker0
# and write this ip to scheduler.yaml
#
# should build with: crystal build src/scheduler.cr --static 
COPY scheduler /usr/share/scheduler
COPY scheduler.yaml /usr/share/scheduler
COPY create-job-cpio.sh /usr/share/scheduler

EXPOSE 3000

WORKDIR /usr/share/scheduler
CMD ["./scheduler"]

