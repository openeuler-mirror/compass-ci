# SPDX-License-Identifier: MulanPSL-2.0+

require "../lib/taskqueue_api"
require "../scheduler/elasticsearch_client"
require "../scheduler/redis_client"
require "../scheduler/constants"
require "./regression_client"
require "./constants.cr"


class StatsWorker
  def initialize()
    @es = Elasticsearch::Client.new
    @tq = TaskQueueAPI.new
    @rc = RegressionClient.new
  end

  def consume_sched_queue(queue_path : String)
    loop do
      begin
        response = @tq.consume_task(queue_path)
      rescue e
        STDERR.puts e.message
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
          begin
            store_stats_es(result_root, job) if result_root
          rescue e
            STDERR.puts e.message
            next
          end
        end

        @tq.delete_task(queue_path + "/in_process", "#{job_id}")
      else
        sleep(2)
      end
    end
  end

  def store_stats_es(result_root : String, job : Job)
    stats_path = "#{result_root}/stats.json"
    raise "#{stats_path} file not exists." unless File.exists?(stats_path)

    stats = File.open(stats_path) do |file|
      JSON.parse(file)
    end

    job_stats = {"stats" => stats.as_h}
    job.update(job_stats)

    error_ids = get_error_ids_by_json(result_root)
    job.update(JSON.parse({"error_ids" => error_ids}.to_json)) unless error_ids.empty?

    @es.set_job_content(job)

    new_error_ids = check_new_error_ids(error_ids, job.id)
    unless new_error_ids.empty?
      STDOUT.puts "send a delimiter task: job_id is #{job.id}"
      @tq.add_task(DELIMITER_TASK_QUEUE, JSON.parse({"error_id" => new_error_ids.sample,
                                         "job_id" => job.id}.to_json))
    end
    puts %({"job_id": "#{job.id}", "job_state": "extract_finished"})
  end

  def check_new_error_ids(error_ids : Array, job_id : String)
    new_error_ids = [] of String
    error_ids.each do |error_id|
      begin
        is_exists = @rc.check_error_id error_id
      rescue e
        STDERR.puts e.message
        next
      end
      next if is_exists
      new_error_ids << error_id
      @rc.store_error_info error_id, job_id
    end
    new_error_ids
  end

  def get_error_ids_by_json(result_root : String)
    error_ids = [] of String
    ERROR_ID_FILES.each do |filename|
      filepath = File.join(result_root, filename)
      next unless File.exists?(filepath)
      content = File.open(filepath) do |file|
        JSON.parse(file)
      end
      error_ids.concat(content.as_h.keys)
    end
    error_ids
  end

  def back_fill_task(queue_path)
    redis_client = Redis::Client.new
    # this queue may have leftover task_ids
    queue_name = "queues/#{queue_path}/in_process"
    begin
      job_ids = redis_client.@client.zrange(queue_name, 0, -1)
      return if job_ids.empty?

      job_ids.each do |job_id|
        @tq.hand_over_task(queue_path, queue_path, job_id.to_s)
      end
    rescue e
      STDERR.puts e.message
    end
  end
end
