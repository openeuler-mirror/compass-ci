FROM debian

RUN apt-get update && \
    apt-get install -y ruby-full && \
    apt-get install -y git && \
    gem install sinatra  && \
    mkdir /app && \
    mkdir /git 

COPY ./myapp.rb /app/


WORKDIR /app

VOLUME /git

CMD ["ruby", "myapp.rb"]
