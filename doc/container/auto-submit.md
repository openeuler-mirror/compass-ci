auto-submit是compass-ci平台的一个微服务，主要功能是接收git-mirror服务发送的消息，并提交job

工作流程如下：

1. auto-submit监听rabbitmq的某个队列

rabbitmq是一个消息队列，可以异步传送消息。git-mirror的消息即是发送给rabbitmq

2. 解析消息

从消息中获取repo信息以及submit job的参数。若没有解析到submit命令相关配置，不会提交job。若最新commit比较老，在两个月以上，则不会提交job。

3. 将解析的参数组合成submit命令，提交job
