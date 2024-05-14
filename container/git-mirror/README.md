git-mirror是compass-ci平台的一个微服务，主要功能是监控上游仓库的变化并触发测试

1. 首先需要配置监控的上游仓库

配置文件路径为：
```
/etc/compass-ci/defaults/upstream-config
```
格式为：
```
---
upstreams:
- url: https://gitee.com/compass-ci/upstream-repos.git
  location: upstream
  git_repo: u/upstream-repos/upstream-repos
```
其中，url所指向的git仓是需要监控的上游仓库的一个集合，配置方式可参考[README](https://gitee.com/compass-ci/upstream-repos/blob/master/README.md)

location则是存放仓库的目录名，一般定义成工程名相同就好了。

为了能够自动更新这个仓库，该仓库需要把自身的信息也加入仓库中，类似于自包含。git_repo则是仓库自身的信息在仓库中的相对路径。

2. git-mirror load仓库中的文件，把需要监控的上游仓库信息读取到内存中。

3. 遍历这些仓库信息，把这些仓库clone到本地，并记录最新的commit信息。仓库存储目录为/srv/git。

4. 对已经clone下来的仓库轮流做git fetch操作来拉取更新。

5. 比较最新的commit和存储的commit信息，若有变化，则发送消息去触发下一个服务提交测试job。


