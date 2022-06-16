# meaning
The submission time of the task, calculated from the time the server receives the task

# where set it
compass-ci/src/lib/job.cr
```
    set_time("submit_time")

    ....

    def set_time(key)
        self[key] = Time.local.to_s("%Y-%m-%dT%H:%M:%S+0800")
    end
```
