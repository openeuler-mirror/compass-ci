# 数据处理背景：
  compass-ci 的每个job的运行结果将会上传到服务器，且每个job对应自己独立的result_root, 如：
    ```
    /srv/result/build-pkg/2021-05-08/dc-8g/openeuler-20.03-pre-aarch64/archlinux-packages--fcgi-trunk-HEAD/crystal.2300321
    ```
  其结果也以日志的形式保存，如下：
    ```
    boot-time  build-pkg  dmesg  heartbeat  job.sh  job.yaml  meminfo.gz  output  program_list  stderr  stdout  time-debug
    ```
  这些日志形式的结果将难以用作后续的数据分析服务，例如build-pkg这个日志：
    ```
    ...
    fcgiapp.c:1717:22: warning: comparison between signed and unsigned integer expressions [-Wsign-compare]
           if(headerLen < sizeof(header)) {
                        ^
    ...
    ```
  这段日志是我们在一次构建测试中（构建fcji-2.4.2-2），我们发现了的一个编译错误，我们想要追溯到这个错误在对应的repo中是哪次commit中引入,
  而像这样的报错信息在整个日志中，没有特殊的标记，其它服务不能简单的识别这3行日志就是个error。
  因此我们需要把这样存在日志中的信息进行提取，输出一个较为规律的数据，这个例子中提取的error信息，我们称之为**error_id**, 例如：
    ```
    fcgiapp.c:warning:comparison-between-signed-and-unsigned-integer-expressions[-Wsign-compare].fail: 1
    ```
  在数据后处理中，我们对任何一个error_id都会以fail结尾，这样做可以方便我们bisect服务准确识别到job中的error，并针对这个error_id去追溯具体是那次commit引入了这个问题。

  此外，job中每发现一个error_id，都会附带一个数字“1”，一个job所有提取出来的error_id最终会输出到一个与日志同名的josn文件，如：
    ```
    /srv/result/build-pkg/2021-05-08/dc-8g/openeuler-20.03-pre-aarch64/archlinux-packages--fcgi-trunk-HEAD/crystal.2300321/build-pkg.json
    {
      "build-pkg.fcgiapp.c:warning:comparison-between-signed-and-unsigned-integer-expressions[-Wsign-compare].fail": [
        1
      ],
      ...
    }
    ```
  这个error_id每出现一次，就会在error_id对应的数据中追加1，
  最后这个error_id会也与它日志提取出来的结果合并，汇总为stats.json，如：
    ```
    {
      "build-pkg.fcgiapp.c:warning:comparison-between-signed-and-unsigned-integer-expressions[-Wsign-compare].fail": 1,
      ...
    }
    ```
  最后提取出来的数据会按job存入ES DB, 这样处理的好处如下:
    - 对于构建测试中发现的error_id， 可以把每个error_id 存入regression index， 便于bisect追溯首次引入问题的commit
    - 对于功能测试，可以快速统计出error数量等

# 数据处理流程：
  按照上文中的例子， 数据处理实现流程如下
  ```
	     extract-stats service got a job_id(crystal.2300321)
	     		 |
			 v
	     get job(info) from ES/jobs/_doc/$job_id
	     		 |
			 v
	     call compass-ci/sbin/result $result_root (/srv/result/build-pkg/2021-05-08/dc-8g/openeuler-20.03-pre-aarch64/archlinux-packages--fcgi-trunk-HEAD/crystal.2300321)
                         |
                         |
                         v
	     compass-ci/sbin/result extract all progrom list:
				eg: ['build-pkg', 'kmsg', ... ]
			 |
			 v
	     $progrom_list.each do |progrom|
			 |
			 |  lkp-tests/stats/$program < $result_root/$program > $tmpfile
			 |	eg: lkp-tests/stats/build-pkg < $result_root/build-pkg > $tmpfile
			 |	 |
			 |	 v
			 |  lkp-tests/sbin/dump-stat < $tmpfile
			 |	 |
			 |	 v
			 |  $result_root/$program.json
			 |	eg: /srv/result/build-pkg/2021-05-08/dc-8g/openeuler-20.03-pre-aarch64/archlinux-packages--fcgi-trunk-HEAD/crystal.2300321/build-pkg.json
			 v
	     merge all $program.json
			 |
			 v
	     $result_root/stats.json
			 |	eg: /srv/result/build-pkg/2021-05-08/dc-8g/openeuler-20.03-pre-aarch64/archlinux-packages--fcgi-trunk-HEAD/crystal.2300321/stats.json
			 v
	     extract-stats update stats.json --> ES_DB/jobs/_doc/crystal.2300321
  ```
