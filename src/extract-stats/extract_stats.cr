# SPDX-License-Identifier: MulanPSL-2.0+

require "./constants"
require "./stats_worker"

module ExtractStats

  # Consume scheduler queue
  def self.in_extract_stats()
    self.back_fill_task
    STATS_WORKER_COUNT.times do
      Process.fork{
        self.consume_task
      }
    end
  end

  def self.consume_task()
    worker = StatsWorker.new
    worker.consume_sched_queue(EXTRACT_STATS_QUEUE_PATH)
  end

  def self.back_fill_task()
    worker = StatsWorker.new
    worker.back_fill_task(EXTRACT_STATS_QUEUE_PATH)
  end
end
