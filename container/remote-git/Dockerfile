FROM debian

RUN apt-get update && \
    apt-get install -y ruby-full && \
    apt-get install -y git && \
    gem install sinatra  && \
    mkdir /app && \
    mkdir /git

COPY ./remote_git.rb /app/


WORKDIR /app

VOLUME /git

CMD ["ruby", "remote_git.rb"]
