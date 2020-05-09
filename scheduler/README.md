1.how to build exe file <scheduler>
 # install shards, redis -> 2.5.3
 - ./0_shards.sh

 # fix ElasticSearch error
lib/elasticsearch-crystal/src/elasticsearch/api/namespace/common.cr
#L79
 - response = HTTP::Client.post(url: endpoint, body: post_data)
 + response = HTTP::Client.post(url: endpoint, body: post_data, headers: HTTP::Headers{"Content-Type" => "application/json"})
#L82
 - response = HTTP::Client.put(url: endpoint, body: post_data)
 + response = HTTP::Client.put(url: endpoint, body: post_data, headers: HTTP::Headers{"Content-Type" => "application/json"})

 # build it
 - ./build.sh

2.how to debug <scheduler>
 # stop running scheduler server
 - docker stop s001-alpine

 # prepare scheduler.yaml, change localhost to docker0's ip (like 172.17.0.1)
 - ifconfig docker0

 # cp (?? share operate)
 - copy /c/lkp-tests/sbin/create-job-cpio.sh .
 - chmod 777 ./create-job-cpio.sh

 # prepare public directory for program use
 - mkdir public
 - chmod 777 public

 # run
 - ./scheduler

3.how to build docker image <like sch-ruby-a:v0.00d>
 # copy program
 - cp ./scheduler ../container/scheduler/
 - cp ./create-job-cpio.sh ../container/scheduler/
 - cp ./scheduler.yaml ../container/scheduler/

 # go to container
 - cd ../container/scheduer

 # build it
 - ./build
