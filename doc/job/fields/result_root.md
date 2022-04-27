# result_root
## meaning
Job field compose rule: /result/{{ suite }}/{{ submit_date }}/{{ tbox_group }}/{{ rootfs }}/{{ others }}/{{ job_id }}

Job results storage path: /srv/$result_root

## example
In job.yaml, it will be display as below:
```
result_root: /result/borrow/2022-03-10/dc-8g/openeuler-20.03-LTS-SP1-aarch64/3600/crystal.5234910
```

## who set it
The sched will create when the job is dispatched.

### example
```
/result/borrow/2022-03-10/dc-8g/openeuler-20.03-LTS-SP1-aarch64/3600/crystal.5234910
boot-time  dmesg  dmesg.json  job.sh  job.yaml  kmsg.json  output  sleep  stats.json  stderr  stderr.json  stdout  time-debug
```

## who use it

on result upload
The job test result will be uploaded to it when the job is finished.

on result examine
User can check out the test result cross the result_root.
