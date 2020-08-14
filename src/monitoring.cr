require "monitoring/monitoring"
require "monitoring/constants"

module Monitoring
  Kemal.run(MONITOR_PORT)
end
