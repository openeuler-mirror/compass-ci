require "../lib/etcd_client"
require "../lib/json_logger"
require "../lib/init_ready_queues"
class GetJob
  def initialize
    @log = JSONLogger.new
    @etcd = EtcdClient.new
    @irqi = InitReadyQueues.instance
  end

  def get_job_by_tbox_type(vmx, tbox_type)
    rqsc = @irqi.get_ready_queues(tbox_type)
    jobs = rqsc[vmx]? || [] of Hash(String, String)
    jobs.each do |job_content|
      submit_custom = "/queues/sched/submit/#{tbox_type}-custom/#{job_content["id"]}"
      rg_ret = @etcd.range(submit_custom)
      next unless rg_ret.count == 1

      _job = job_content.clone
      _job["mvt"] = Time.local.to_s("%Y-%m-%dT%H:%M:%S+0800")

      in_process = "/queues/sched/in_process/#{vmx}/#{job_content["id"]}"
      mv_ret = @etcd.move(submit_custom, in_process, _job.to_json)
      @log.info("move submit_custom to in_process result, #{submit_custom}, #{in_process}, #{mv_ret}")
      return _job if mv_ret
    end

    return nil
  end
end
