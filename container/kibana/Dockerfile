# SPDX-License-Identifier: MulanPSL-2.0+

FROM gagara/kibana-oss-arm64:7.6.2

# docker image borrowed from hub.docker.com/r/gagara/kibana-oss-arm64

MAINTAINER Wu Zhende <wuzhende1@huawei.com>

RUN sed -i 's/server.host: "0"/server.host: "0.0.0.0"/' config/kibana.yml
