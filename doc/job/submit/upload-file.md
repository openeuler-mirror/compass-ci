## 介绍

在某些测试脚本中，常常会需要使用到各种各样的配置。Linux 内核的配置项，一些需要编译的软件的配置等等，配置比较复杂，往往都需要一个配置文件来描述。所以需要一个通用的功能，支持从客户端提交任务时上传需要使用的配置文件到调度器。

## 使用介绍

目前上传文件的默认支持 pkgbuild 以及 ss 字段。下面以 pkgbuild 为例。

假设我们现在有一个 linux 的配置文件, 路径为本地的 /root/config.5.10-xx：
```
...
CONFIG_LOCK_DEBUGGING_SUPPORT=y
CONFIG_ARCH_USE_CMPXCHG_LOCKREF=y
CONFIG_HAS_DMA=y
CONFIG_HAVE_CONTEXT_TRACKING=y
CONFIG_SERIO=y
CONFIG_OF_GPIO=y
...
```
我们想要使用这个配置文件，并使用 pkgbuild 来构建内核。提交 pkgbuild job:
```
submit build-linux.yaml config=/root/config.5.10-xx
```

好了，无需其他操作，程序会自动处理并上传到服务器，并使用对应的 config。

> pkgbuild 要使用上传好的文件，需要对应的脚本来做适配。

## 设计逻辑

### 总体流程

  —> 1.客户端第一次提交, job.yaml 中携带了支持的文件上传字段

  - pkgbuild 的 config 字段：
    ```
    suite: pkgbuild
    config: config.5.10-xxx
    ```
  - ss 字段下，ss.\*.config\* 规则的字段：
    ```
    ...
    ss:
        git:
            ....
            configx: config.5.10-xxx
            ....
        mysql:
            configxx: config.5.10-xxx
    ...
    ```

  —> 2.调度器处理job，包含三个步骤：

  - 如果 job 存在字段 upload_fields，处理 upload_fields 中的文件信息，保存到服务器
  - 如果 job 不存在字段 upload_fields，检查 job 是否需要上传文件。
    - 这个文件已在服务器，不做处理，
    - 不在服务器，返回需要上传的字段详情，通知客户端重新提交并携带文件信息。
  - 最后一步，将文件最终上传的 url（initrd 链接）保存到变量 "upload_file_url", 以供测试脚本所读取下载


### 调度器方面：

第一阶段：处理客户端 job 中携带的 upload_fields（包含文件信息），这应该是一个列表，列表中的每一项都代表需要上传的文件信息。处理函数 **`process_upload_fields` ,** 位于  $CCI_SRC/src/lib/job.cr .

- 寻找 job 中是否有 upload_fields 字段，如果有，进行下一步。
- 依次迭代 upload_fields 中的每一项，执行  store_upload_file 函数保存文件到服务器。保存目录的结构为：/srv/cci/user-files/$suite/$field_name/$filename
  > 对于pkgbuild类型的 job，目录结构则为：/srv/cci/user-files/$suite/$pkg_name/$field_name/$filename
- 执行 reset_upload_field 函数，删除 upload_fields 每一项中的 content 字段，添加 save_dir 字段保留文件信息。

下面是一个示例：

```yaml
# 调度器保存文件执行前---------------------
upload_fields:
  ss.linux.config:
    md5: 8283b295ef0d03af318faa2ed2c5d5c8
    file_name: kconfig-xx
    content: |-xxxxx

# 调度器保存文件执行后---------------------
upload_fields:
  ss.linux.config:
    md5: 8283b295ef0d0123218faa2ed2c5d5c8
    file_name: kconfig-xx
    save_dir: /srv/cci/user-files/.....
```

第二阶段：检查  job 中是否有符合要求的文件上传字段，并从里面获取 upload_fields (只包含上传文件的字段，需要返回给客户端处理) 。目前符合要求的上传字段为  ss.*.config* 以及 config (suite: build-pkg) 字段。

处理的核心函数 `generate_upload_fields` , 位于 $CCI_SRC/src/lib/job.cr。

检查 job  是否有 ss.*.config* 以及 config (suite: build-pkg) 字段。

> $CCI_SRC/src/lib/user_uploadfiles_fields_config.yaml 可以配置符合规则的job和字段来支持上传文件。

如果有，获取字段值（filepath），构建文件路径：/srv/cci/user-files/$suite/$field_name/$filename。
 > 对于pkgbuild类型的 job，目录结构则为：/srv/cci/user-files/$suite/$pkg_name/$field_name/$filename

- 检查上述的文件路径是否存在，如果存在，export 变量 "upload_file_url", 值为文件的url, 以供测试机下载和载入。
> http://$INITRD_HTTP_HOST:$INITRD_HTTP_PORT/cci/user-files/pkgbuild/linux/config/config.5.10-xx
- 如果不存在，添加到 upload_fields 列表，每一项为需要上传文件的字段，如 ss.linux.config ，返回给客户端，通知客户端上传该字段的文件内容：

```yaml
  {
    "errcode": "RETRY_UPLOAD",
    "upload_fields: $upload_fields
  }
```

### 客户端方面：

客户端应该要经历两个阶段。

第一个阶段：提交 job ，解析调度器返回的消息，如解析到 ”errcode“ == ”RETRY_UPLOAD“, 代表调度器通知客户端需要上传内容。

解析返回消息中 upload_fields 的内容，并构造新的 upload_fields, 里面包含了调度器保存文件所需的各种信息（md5,field,filename,content）。

具体函数内容在 $LKP_SRC/lib/upload_field_pack.rb ，核心为 `pack` 函数：

- 迭代从调度器返回的 upload_fields ，对每个 upload_field ，获取对应的字段值，打包 md5, content， filename 字段。假设某个 upload_field 为 `ss.linux.config` 。
    - 获取 ss.linux.config 字段的值，如 kconfig-xx，应该是一个文件。检查 kconfig-xx 是否存在（本地目录）。
    - 不存在，raise 异常，上传出错。
    - 存在，执行 `generate_upload_field_hash` 函数, 获取  kconfig-xx 文件的 md5、文件名filename(basename) 、内容 content，填充到新的 upload_fields 中的一项。

```yaml
# 填充前---------------------
upload_fields:
  ss.linux.config:

# 填充后---------------------
upload_fields:
  ss.linux.config:
    md5: 8283b295ef0d0123218faa2ed2c5d5c8
    file_name: kconfig-xx
	content: xxxxxx
```

第二步：客户端再次提交此 job ，此时携带了 upload_fields, 包含了需要上传的文件信息。

### 对于 ss 字段中 pkgbuild的特殊处理：

由于 ss 字段中的 pkgbuild 任务会在服务器提交，那么对于我们的文件上传流程，需要做一些处理，默认的流程为：

  —> 1.客户端第一次提交, 有 ss.linux.config 字段

  —> 2.调度器检查到 /srv/cci/user-files/$suite/ss.linux.config/$filename 无文件，返回，通知上传文件

  —> 3.客户端第二次提交，携带上传的文件信息。

  —> 4.调度器保存文件到 /srv/cci/user-files/$suite/ss.linux.config/$filename ，提交 ss 中的 pkgbuild

  —> 5.调度器接收到 pkgbuild 任务，检查 /srv/cci/user-files/build-pkg(pkgbuild)/$pkg_name/config/$filename 文件不存在，通知客户端上传文件。

可以看到，最后一步又通知了一遍客户端上传文件，实际我们已经上传好了文件到 $suite/ss.linux.config/$filename, 这样容易出现异常。

那么现在需要的就是在 ss 的 pkgbuild 任务提交前，关联 /srv/cci/user-files/$suite/ss.linux.config/$filename 到  /srv/cci/user-files/$suite/build-pkg(pkgbuild)/$pkg_name/$filename。这样在 ss 的 pkgbuild job 提交时，就能检测到对应目录文件的存在性，无需重复上传。

修改上述流程的第四步：

 —> 4. 调度器保存文件到 /srv/cci/user-files/$suite/ss.linux.config/$filename。
 关联 /srv/cci/user-files/$suite/ss.linux.config/$filename 到  /srv/cci/user-files/$suite/build-pkg(pkgbuild)/$pkg_name/$filename。最后提交 ss  的 pkgbuild。


## FAQ

- This file not found in server, so we need upload it, but we not found in local.....
  > 这个文件不在服务器，我们需要上传，但是在本地找不到指定的文件，建议最好指定文件的绝对路径

