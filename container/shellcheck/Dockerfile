FROM debian
MAINTAINER wangchenglong17@huawei.com
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && \
    apt-get install -y shellcheck
VOLUME /shellbox
WORKDIR /shellbox
CMD ["/bin/bash"]
