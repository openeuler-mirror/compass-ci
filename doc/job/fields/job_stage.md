# job_stage
## meaning
Dynamic job running status, show job's life cycle. 

## example
```
submit -> boot -> running -> post_run -> manual_check -> renew -> finish
```

## who set it
The sched will set job status 

## who use it
Container service lifecycle push the process from start to finish by job_stage.

## refer to
[lifecycle](https://gitee.com/wu_fengguang/compass-ci/doc/development/lifecycle.md)
