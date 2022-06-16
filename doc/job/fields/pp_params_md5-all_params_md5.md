# meaning

pp_params_md5 is the md5 value of pp.*.*

all_params_md5 is the md5 value of pp.*.* and some command params.

command params is:tbox_group/os/os_arch/os_version.

if two jobs's command params and pp params are the same, then they pp_params_md5 and all_params_md5 are the same. So these two fields can be used to identify jobs.

# where set it
src/lib/job.cr
```
  private def set_params_md5
    flat_pp_hash = Hash(String, JSON::Any).new
    flat_hash(hash["pp"].as_h? || flat_pp_hash, flat_pp_hash)
    hash["pp_params_md5"] = JSON::Any.new(get_md5(flat_pp_hash))

    all_params = flat_pp_hash
    COMMON_PARAMS.each do |param|
      all_params[param] = hash[param]
    end

    hash["all_params_md5"] = JSON::Any.new(get_md5(all_params))
  end
```

# where use it
we can use all_params_md5 to search the jobs with same pp params and common params. if the number of these jobs > **max_run**, this will throw an error.

src/lib/job.cr
```
  private def checkout_max_run
    return unless hash["max_run"]?

    query = {
      "size" => 1,
      "query" => {
        "term" => {
          "all_params_md5" => hash["all_params_md5"]
        }
      },
      "sort" =>  [{
        "submit_time" => { "order" => "desc", "unmapped_type" => "date" }
      }],
      "_source" => ["id", "all_params_md5"]
    }
    total, latest_job_id = @es.get_hit_total("jobs", query)

    msg = "exceeds the max_run(#{hash["max_run"]}), #{total} jobs exist, the latest job id=#{latest_job_id}"
    raise msg if total >= hash["max_run"].to_s.to_i32
  end

```
