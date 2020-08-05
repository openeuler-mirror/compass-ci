require "../lib/taskqueue_api"
require "../scheduler/elasticsearch_client"
require "../scheduler/constants"

class StatsWorker
  def initialize()
    @es = Elasticsearch::Client.new
    @tq = TaskQueueAPI.new
  end

  def consume_sched_queue(queue_path : String)
    loop do
      begin
        response = @tq.consume_task(queue_path)
      rescue e
        puts e.message
        next
      end
      if response[0] == 200
        job_id= JSON.parse(response[1].to_json)["id"]

        job = @es.get_job(job_id.to_s)
        if job
          result_root = job.result_root
          # extract stats.json
          system "#{ENV["CCI_SRC"]}/sbin/result2stats #{result_root}"
          # storage job to es
          storage_stats_es(result_root, job) if result_root
        end

        @tq.delete_task(queue_path + "/in_process", "#{job_id}")
      else
        sleep(2)
      end
    end
  end

  def storage_stats_es(result_root : String, job : Job)
    stats_path = "#{result_root}/stats.json"
    stats = File.open(stats_path) do |file|
        JSON.parse(file)
    end
    job_stats = {"stats" => stats.as_h}
    job.update(job_stats)

    @es.set_job_content(job)
  end
end
