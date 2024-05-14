# job_stage
## meaning
Dynamic job running status, show job's life cycle. 

## example
```
submit -> boot -> running -> wait_peer -> started -> post_run -> manual_check -> renew -> uploaded -> finish -> complete
```

In cluster testing, the service node will directly enter 'started' stage,
while the client nodes will first "wait_peer", waiting for all client nodes
reach this point, then go ahead together.

## who set it
The sched will set job status 

## who use it
Container service lifecycle push the process from start to finish by job_stage.

## refer to
[lifecycle](https://gitee.com/openeuler/compass-ci/doc/development/lifecycle.md)
