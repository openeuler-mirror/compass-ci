
class Sched

  private def generate_plain_text_table(hosts, fields) : String
    # Calculate column widths
    col_widths = fields.map do |field|
      header_size = field.size
      max_content_size = hosts.map { |host| (host[field]? || "").size }.max || 0
      {header_size, max_content_size}.max
    end

    # Build header row
    header = fields.zip(col_widths).map { |field, width| field.ljust(width) }.join("  ")
    lines = [header]

    # Build data rows
    hosts.each do |host|
      row = fields.zip(col_widths).map do |field, width|
        value = host[field]? || ""
        value.ljust(width)
      end.join("  ")
      lines << row
    end

    # Join all lines with newlines
    lines.join("\n")
  end

  # Helper method to format uptime with days, hours, and minutes
  def format_uptime(minutes)
    if minutes < 60
      "#{minutes}M"
    else
      hours = minutes // 60
      remaining_minutes = minutes % 60

      if hours < 24
        "#{hours}H #{remaining_minutes}M"
      else
        days = hours // 24
        remaining_hours = hours % 24
        "#{days}D #{remaining_hours}H #{remaining_minutes}M"
      end
    end
  end

  # Helper method to format memory size
  def format_memory(memory_in_mb)
    return "N/A" if memory_in_mb.nil?

    if memory_in_mb < 1024
      "#{memory_in_mb} MB"
    elsif memory_in_mb < 1024 * 1024
      "#{(memory_in_mb / 1024.0).round(2)} GB"
    else
      "#{(memory_in_mb / (1024.0 * 1024.0)).round(2)} TB"
    end
  end

  def api_dashboard_hosts(env)
    # Filter parameters
    selected_arches = env.params.query.fetch_all("arch")
    selected_tbox_types = env.params.query.fetch_all("tbox_type")
    selected_is_remote = env.params.query.fetch_all("is_remote")
    selected_my_accounts = env.params.query.fetch_all("my_account")
    selected_suites = env.params.query.fetch_all("suite")
    selected_load = env.params.query.fetch_all("load")
    has_job = env.params.query.fetch_all("has_job")

    # Sort parameters
    sort_field = env.params.query["sort"]? || "hostname"
    sort_order = env.params.query["order"]? || "asc"

    # Field selection
    selected_fields = env.params.query["fields"]?.try(&.split(',')) || %w[
      hostname
      arch
      nr_cpu
      nr_disks
      nr_vm
      nr_container
      tbox_type
      active_time
      reboot_time
      uptime_minutes

      job_id
      suite
      my_account

      freemem
      freemem_percent
      disk_max_used_percent
      cpu_idle_percent
      cpu_iowait_percent
      cpu_system_percent
      disk_io_util_percent
    ]
    # skipped fields to avoid too long line
    # is_remote
    # boot_time
    # network_util_percent
    # network_errors_per_sec

    field_display_name = {
      "hostname"               => "hostname",
      "arch"                   => "arch",
      "nr_cpu"                 => "NR<br>cpu",
      "nr_disks"               => "NR<br>disk",
      "nr_vm"                  => "NR<br>vm",
      "nr_container"           => "NR<br>dc",
      "tbox_type"              => "Type",
      "is_remote"              => "Remote",
      "boot_time"              => "Boot<br>time",
      "active_time"            => "Active<br>time",
      "reboot_time"            => "Reboot<br>time",
      "uptime_minutes"         => "Uptime",

      "job_id"                 => "Job ID",
      "suite"                  => "Suite",
      "my_account"             => "Account",

      "freemem"                => "Free<br>mem",
      "freemem_percent"        => "Free<br>mem%",
      "disk_max_used_percent"  => "DSK<br>use%",
      "cpu_idle_percent"       => "CPU<br>id%",
      "cpu_iowait_percent"     => "CPU<br>wa%",
      "cpu_system_percent"     => "CPU<br>sy%",
      "disk_io_util_percent"   => "IO<br>util%",
      "network_util_percent"   => "Net<br>util%",
      "network_errors_per_sec" => "Net<br>err/s"
    }

    output_format = env.params.query["output"]? || "html"

    # Filter hosts
    filtered_hosts = @hosts_cache.hosts.select do |_, hi|
      (selected_arches.empty? || selected_arches.includes?(hi.arch)) &&
      (selected_tbox_types.empty? || selected_tbox_types.includes?(hi.tbox_type)) &&
      (selected_is_remote.empty? || hi.is_remote == (selected_is_remote.first == "true")) &&
      (selected_my_accounts.empty? || selected_my_accounts.includes?(hi.my_account)) &&
      (selected_suites.empty? || selected_suites.includes?(hi.suite)) &&
      (has_job.empty? || (hi["job_id"] != 0) == (has_job.first == "true"))
    end

    # Load filtering
    filtered_hosts = filtered_hosts.select do |_, hi|
      selected_load.empty? || selected_load.any? do |load|
        cpu_idle = hi.cpu_idle_percent
        case load
        when "heavy"  then cpu_idle < 20
        when "medium" then cpu_idle >= 20 && cpu_idle < 40
        when "light"  then cpu_idle >= 40
        else false
        end
      end
    end

    # Sort hosts
    if HostInfo::UINT32_KEYS.includes?(sort_field) || HostInfo::UINT32_METRIC_KEYS.includes?(sort_field)
      sorted_hosts = filtered_hosts.values.sort_by! do |host|
        host.hash_uint32[sort_field]? || 0
      end
    elsif HostInfo::STRING_KEYS.includes?(sort_field)
      sorted_hosts = filtered_hosts.values.sort_by! do |host|
        host.hash_str[sort_field]? || ""
      end
    elsif HostInfo::BOOL_KEYS.includes?(sort_field)
      sorted_hosts = filtered_hosts.values.sort_by! do |host|
        (host.hash_bool[sort_field]? || false).to_s
      end
    else
      sorted_hosts = filtered_hosts.values
    end
    # sorted_hash = Hash.new(sorted_hosts)
    sorted_hosts.reverse! if sort_order == "desc"

    # Process hosts into uniform hashes
    processed_hosts = sorted_hosts.map do |host|
      host_data : Hash(String, String) = {
        "id"                => host.id.to_s,
        "hostname"          => host.hostname,
        "arch"              => host.arch,
        "nr_cpu"            => host.nr_cpu.to_s,
        "nr_disks"          => host.nr_disks?.to_s,
        "nr_vm"             => host.nr_vm?.to_s,
        "nr_container"      => host.nr_container?.to_s,
        "tbox_type"         => host.tbox_type,
        "is_remote"         => host.is_remote ? "Remote" : "Local",
        "has_job"           => host.job_id == 0 ? "No" : "Yes",

        "boot_time"         => !host.boot_time? ? "N/A" : Time.unix(host.boot_time).to_s("%Y-%m-%d %H:%M"),
        "active_time"       => !host.active_time? ? "N/A" : ((Time.utc.to_unix - host.active_time) / 60).to_s,
        "reboot_time"       => !host.reboot_time? ? "N/A" : Time.unix(host.reboot_time).to_s("%Y-%m-%d %H:%M"),
        "uptime_minutes"    => !host.uptime_minutes? ? "N/A" : format_uptime(host.uptime_minutes),

        "active_status"     => !host.active_time? ? "inactive" : (Time.utc.to_unix - host.active_time <= 600 ? "active" : "inactive"),
        "reboot_status"     => !host.reboot_time? ? "unknown" : (Time.utc.to_unix > host.reboot_time ? "needs_reboot" : "ok"),

        "freemem"                 => format_memory(host.freemem),
        "freemem_percent"         => host.freemem_percent?.to_s,
        "disk_max_used_percent"   => host.disk_max_used_percent?.to_s,
        "disk_max_used_string"    => host.disk_max_used_string? || "",
        "cpu_idle_percent"        => host.cpu_idle_percent?.to_s,
        "cpu_iowait_percent"      => host.cpu_iowait_percent?.to_s,
        "network_errors_per_sec"  => host.network_errors_per_sec?.to_s,

        "freemem_percent_class" => case (val = host.freemem_percent? || 99)
          when 0..20 then "critical-bg"
          when 21..40 then "warning-bg"
          else "healthy-bg"
        end,

        "disk_max_used_class" => case (val = host.disk_max_used_percent? || 0)
          when 90..100 then "text-critical"
          when 80..89 then "text-warning"
          else ""
        end,

        "cpu_iowait_class" => case (val = host.cpu_iowait_percent? || 0)
          when 10..100 then "text-critical"
          when 2..9 then "text-warning"
          else ""
        end,

        "network_errors_class" => (host.network_errors_per_sec || 0) > 0 ? "text-critical" : "",

      }

        host_data["active_status_class"] = host_data["active_status"] == "active" ? "text-healthy" : "text-critical"
        host_data["reboot_status_class"] = host_data["reboot_status"] == "ok" ? "text-healthy" : "text-critical"
        host_data["freemem_percent_style"] = "background: linear-gradient(90deg, #{"%02x" % (255 * (100 - host.freemem_percent)/100)}0000 0%, #{"%02x" % (255 * (100 - host.freemem_percent)/100)}0000 #{host.freemem_percent}%, #ffffff00 #{host.freemem_percent}%);" if host.freemem_percent?

      if host.job_id != 0
        host_data["job_id"] = host.job_id.to_s
        host_data["suite"] = host.suite
        host_data["my_account"] = host.my_account
      else
        host_data["job_id"] = ""
        host_data["suite"] = ""
        host_data["my_account"] = ""
      end
      host_data
    end

    # Generate output based on the format
    if output_format == "text"
      env.response.content_type = "text/plain"
      return response = generate_plain_text_table(processed_hosts, selected_fields)
    end

    # Counts for filters
    arch_counts = Hash(String, Int32).new(0)
    tbox_counts = Hash(String, Int32).new(0)
    remote_counts = Hash(String, Int32).new(0)
    hasjob_counts = Hash(String, Int32).new(0)
    account_counts = Hash(String, Int32).new(0)
    suite_counts = Hash(String, Int32).new(0)

    processed_hosts.each do |host|
      arch_counts[host["arch"]] += 1
      tbox_counts[host["tbox_type"]] += 1
      remote_counts[host["is_remote"]] += 1
      hasjob_counts[host["has_job"]] += 1
      unless host["job_id"].empty?
        account_counts[host["my_account"]] += 1
        suite_counts[host["suite"]] += 1
      end
    end

    # Define filters in a unified data structure
    filters = [
      {
        type:        :checkbox_group,
        name:        "arch",
        title:       "Architecture",
        options:     arch_counts,
        selected:    selected_arches,
      },
      {
        type:        :checkbox_group,
        name:        "tbox_type",
        title:       "Type",
        options:     tbox_counts,
        selected:    selected_tbox_types,
      },
#     {
#       type:        :checkbox_group,
#       name:        "is_remote",
#       title:       "Remote Status",
#       options:     remote_counts,
#       selected:    selected_is_remote,
#     },
      {
        type:        :checkbox_group,
        name:        "my_account",
        title:       "Accounts",
        options:     account_counts,
        selected:    selected_my_accounts,
      },
      {
        type:        :checkbox_group,
        name:        "suite",
        title:       "Suites",
        options:     suite_counts,
        selected:    selected_suites,
      },
#     {
#       type:        :checkbox_group,
#       name:        "load",
#       title:       "Load Level",
#       options:     {"heavy" => nil, "medium" => nil, "light" => nil},
#       selected:    selected_load,
#     },
      {
        type:        :checkbox_group,
        name:        "has_job",
        title:       "Running Job",
        options:     hasjob_counts,
        selected:    has_job,
      },
    ]

    # Build HTML with modern styling
    response = String.build do |html|
      html << <<-HTML
        <!DOCTYPE html>
        <html>
        <head>
          <title>Host Dashboard</title>
          <meta http-equiv="refresh" content="600">
          <link href="https://fonts.googleapis.com/css2?family=Roboto+Mono:wght@300;400;500&family=Roboto:wght@300;400;500&display=swap" rel="stylesheet">
          <style>
            :root { font-family: 'Roboto', sans-serif; }
            code, .mono { font-family: 'Roboto Mono', monospace; }
            body { margin: 2rem; background: #f0f4f8; }
            .filter-container { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1rem; }
            .filter-group { background: white; padding: 1rem; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.12); }
            table { background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.12); margin-top: 2rem; }
            th { background: #f7cac9; color: white; padding: 0.3rem; }
            td { padding: 0.5rem; border-bottom: 1px solid #ecf0f1; }
            tr:hover { background: #f8f9fa; }
            .text-critical { color: #e74c3c; }
            .text-warning { color: #f39c12; }
            .text-healthy { color: #2ecc71; }
            .critical-bg { background: #f8d7da; }
            .warning-bg { background: #fff3cd; }
            .healthy-bg { background: #d4edda; }
            a { color: #3498db; text-decoration: none; }
            a:hover { text-decoration: underline; }
          </style>
        </head>
        <body>
          <h1>Host Dashboard</h1>
          <form method="get">
            <div class="filter-container">
      HTML

      # Unified filter rendering
      filters.each do |filter|
        html << "<div class=\"filter-group\"><strong>#{filter[:title]}</strong>"
        case filter[:type]
        when :checkbox_group
          filter[:options].each do |opt, count|
            checked = filter[:selected].includes?(opt) ? "checked" : ""
            html << <<-HTML
              <label style="display: block; margin: 4px 0;">
                <input type="checkbox" name="#{filter[:name]}" value="#{opt}" #{checked}>
                #{opt} <small>(#{count})</small>
              </label>
            HTML
          end
        when :select
          html << "<select name=\"#{filter[:name]}\" style=\"margin-left: 8px;\">"
          filter[:options].each do |opt, count|
            selected = filter[:selected].includes?(opt) ? "selected" : ""
            html << "<option value=\"#{opt}\" #{selected}>#{opt} (#{count})</option>"
          end
          html << "</select>"
        end
        html << "</div>"
      end

      html << <<-HTML
            </div>
            <button type="submit" style="margin-top: 1rem; padding: 8px 16px; background: #3498db; color: white; border: 1px; border-radius: 4px;">Apply Filters</button>
          </form>
      HTML

      # Table rendering with health/utilization data
      # html << "<table>"
      html << "<table><thead><tr><th>#</th>"
      selected_fields.each do |field|
        current_order = sort_field == field ? (sort_order == "asc" ? "desc" : "asc") : "asc"
        params = HTTP::Params.build do |form|
          env.params.query.each { |k, vs| vs.split(",").each { |v| form.add(k, v) unless k == "sort" || k == "order" } }
          form.add("sort", field)
          form.add("order", current_order)
        end
        html << "<th><a href=\"?#{params}\">#{field_display_name[field]}</a></th>"
      end
      html << "</tr></thead><tbody>"

      processed_hosts.each_with_index do |host, idx|
        html << "<tr><td>#{idx + 1}</td>"
        selected_fields.each do |field|
          value = host[field]? || ""
          cell = case field
          when "hostname"
            "<a href=\"/host/#{host["id"]}\">#{value}</a>"
          when "freemem_percent"
            "<span class=\"#{host["freemem_percent_class"]}\" style=\"#{host["freemem_percent_style"]} padding: 2px 4px; border-radius: 3px;\">#{value}%</span>"
          when "disk_max_used_percent"
            "<span class=\"#{host["disk_max_used_class"]}\">#{value}%</span>"
          when "cpu_iowait_percent"
            "<span class=\"#{host["cpu_iowait_class"]}\">#{value}%</span>"
          when "network_errors_per_sec"
            "<span class=\"#{host["network_errors_class"]}\">#{value}</span>"
          when "active_time"
            "<span class=\"#{host["active_status_class"]}\">#{value}</span>"
          when "reboot_time"
            "<span class=\"#{host["reboot_status_class"]}\">#{value}</span>"
          else
            value
          end
          html << "<td>#{cell}</td>"
        end
        html << "</tr>"
      end

      # html << "</table></body></html>"
      html << "</tbody></table></body></html>"
    end

    env.response.content_type = "text/html"
    response
  end

end
