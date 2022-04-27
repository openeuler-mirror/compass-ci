# submit_date
## meaning
The date when submit a job

## example
In job.yaml, it will be display as below:
```
submit_date: "2022-03-11"
```

## who set it
When you submit a job, sched will record the date.

## who use it
This field will be part of $result_root, to combine a job result storage path.

```
self["result_root"] = File.join("/result/#{suite}/#{submit_date}/#{tbox_group}/#{rootfs}", "#{sort_pp_params}", "#{id}")
```
