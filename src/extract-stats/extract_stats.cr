# SPDX-License-Identifier: MulanPSL-2.0+

require "./constants"
require "./stats_worker"

module ExtractStats

  # Consume scheduler queue
  def self.in_extract_stats()
    worker = StatsWorker.new
    worker.consume_sched_queue(EXTRACT_STATS_QUEUE_PATH)
  end
end
