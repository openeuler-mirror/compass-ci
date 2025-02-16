
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

  def api_dashboard_hosts(env)
    # Filter parameters
    selected_arches = env.params.query.fetch_all("arch")
    selected_tbox_types = env.params.query.fetch_all("tbox_type")
    selected_is_remote = env.params.query["is_remote"]? || ""
    selected_my_accounts = env.params.query.fetch_all("my_account")
    selected_suites = env.params.query.fetch_all("suite")
    selected_load = env.params.query.fetch_all("load")
    has_job = env.params.query.has_key?("has_job")

    # Sort parameters
    sort_field = env.params.query["sort"]? || "hostname"
    sort_order = env.params.query["order"]? || "asc"

    # Field selection
    selected_fields = env.params.query["fields"]?.try(&.split(',')) || [
      "hostname", "arch", "nr_cpu", "freemem_percent", "uptime_minutes",
      "tbox_type", "is_remote", "active_status", "reboot_status"
    ]

    output_format = env.params.query["output"]? || "html"

    # Filter hosts
    filtered_hosts = @hosts_cache.hosts.select do |_, hi|
      (selected_arches.empty? || selected_arches.includes?(hi.arch)) &&
      (selected_tbox_types.empty? || selected_tbox_types.includes?(hi.tbox_type)) &&
      (selected_is_remote.empty? || hi.is_remote == (selected_is_remote == "true")) &&
      (selected_my_accounts.empty? || selected_my_accounts.includes?(hi.my_account)) &&
      (selected_suites.empty? || selected_suites.includes?(hi.suite)) &&
      (has_job ? hi["job_id"] != 0 : true)
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
        host.hash_uint32[sort_field]
      end
    elsif HostInfo::STRING_KEYS.includes?(sort_field)
      sorted_hosts = filtered_hosts.values.sort_by! do |host|
        host.hash_str[sort_field]
      end
    elsif HostInfo::BOOL_KEYS.includes?(sort_field)
      sorted_hosts = filtered_hosts.values.sort_by! do |host|
        host.hash_bool[sort_field].to_s
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
        "is_remote"         => host.is_remote.to_s,

        "boot_time"         => !host.boot_time? ? "N/A" : Time.unix(host.boot_time).to_s("%Y-%m-%d %H:%M"),
        "active_time"       => !host.active_time? ? "N/A" : ((Time.utc.to_unix - host.active_time) / 60).to_s,
        "reboot_time"       => !host.reboot_time? ? "N/A" : Time.unix(host.reboot_time).to_s("%Y-%m-%d %H:%M"),
        "uptime_minutes"    => !host.uptime_minutes? ? "N/A" : host.uptime_minutes.to_s,
        "active_status"     => !host.active_time? ? "inactive" : (Time.utc.to_unix - host.active_time <= 600 ? "active" : "inactive"),
        "reboot_status"     => !host.reboot_time? ? "unknown" : (Time.utc.to_unix > host.reboot_time ? "needs_reboot" : "ok"),

        "freemem"                 => "#{host.freemem} MB",
        "freemem_percent"         => host.freemem_percent?.to_s,
        "disk_max_used_percent"   => host.disk_max_used_percent?.to_s,
        "disk_max_used_string"    => host.disk_max_used_string? || "",
        "cpu_idle_percent"        => host.cpu_idle_percent?.to_s,
        "cpu_iowait_percent"      => host.cpu_iowait_percent?.to_s,
        "network_errors_per_sec"  => host.network_errors_per_sec?.to_s,
      }

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
    account_counts = Hash(String, Int32).new(0)
    suite_counts = Hash(String, Int32).new(0)

    @hosts_cache.hosts.each do |_, host|
      arch_counts[host.arch] += 1
      tbox_counts[host.tbox_type] += 1
      remote_counts[host.is_remote.to_s] += 1
      if host.job_id != 0
        account_counts[host.my_account] += 1 unless host.my_account?
        suite_counts[host.suite] += 1 unless host.suite?
      end
    end

    # Build HTML
    response = String.build do |html|
      html << <<-HTML
        <!DOCTYPE html>
        <html>
        <head>
          <title>Host Dashboard</title>
          <meta http-equiv="refresh" content="10">
          <style>
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #ddd; padding: 4px; text-align: left; }
            tr:nth-child(even) { background-color: #f2f2f2; }
            .healthy { color: #008000; }
            .warning { color: #ffa500; }
            .critical { color: #ff0000; }
            .filter-group { margin: 5px; padding: 5px; border: 1px solid #ccc; }
            label { display: inline-block; margin: 2px 5px; }
          </style>
        </head>
        <body>
      HTML

      # Filters
      html << <<-HTML
        <form method="get">
        #{env.params.query.map { |k, v|
          next if ["arch", "tbox_type", "is_remote", "my_account", "suite", "load", "has_job"].includes?(k)
          v.split(",").map { |val| "<input type=\"hidden\" name=\"#{k}\" value=\"#{val}\">" }.join
        }.join}
      HTML

      # Arch filter
      html << "<div class=\"filter-group\"><strong>Arch:</strong>"
      arch_counts.each do |arch, count|
        checked = selected_arches.includes?(arch) ? "checked" : ""
        html << "<label><input type=\"checkbox\" name=\"arch\" value=\"#{arch}\" #{checked}> #{arch} (#{count})</label>"
      end
      html << "</div>"

      # Tbox type filter
      html << "<div class=\"filter-group\"><strong>Type:</strong>"
      tbox_counts.each do |tbox, count|
        checked = selected_tbox_types.includes?(tbox) ? "checked" : ""
        html << "<label><input type=\"checkbox\" name=\"tbox_type\" value=\"#{tbox}\" #{checked}> #{tbox} (#{count})</label>"
      end
      html << "</div>"

      # Remote filter
      html << "<div class=\"filter-group\"><strong>Remote:</strong>"
      html << "<select name=\"is_remote\">"
      html << "<option value=\"\"#{selected_is_remote.empty? ? " selected" : ""}>All (#{remote_counts.values.sum})</option>"
      html << "<option value=\"true\"#{selected_is_remote == "true" ? " selected" : ""}>Yes (#{remote_counts["true"]})</option>"
      html << "<option value=\"false\"#{selected_is_remote == "false" ? " selected" : ""}>No (#{remote_counts["false"]})</option>"
      html << "</select></div>"

      # Job filter
      html << "<div class=\"filter-group\">"
      html << "<label><input type=\"checkbox\" name=\"has_job\" value=\"true\"#{has_job ? " checked" : ""}> Has Job</label>"
      html << "</div>"

      # Load filter
      html << "<div class=\"filter-group\"><strong>Load:</strong>"
      ["heavy", "medium", "light"].each do |load|
        checked = selected_load.includes?(load) ? "checked" : ""
        html << "<label><input type=\"checkbox\" name=\"load\" value=\"#{load}\" #{checked}> #{load.capitalize}</label>"
      end
      html << "</div>"

      html << "<button type=\"submit\">Apply Filters</button></form>"

      # Table
      html << "<table><thead><tr><th>#</th>"
      selected_fields.each do |field|
        current_order = sort_field == field ? (sort_order == "asc" ? "desc" : "asc") : "asc"
        params = HTTP::Params.build do |form|
          env.params.query.each { |k, vs| vs.split(",").each { |v| form.add(k, v) unless k == "sort" || k == "order" } }
          form.add("sort", field)
          form.add("order", current_order)
        end
        html << "<th><a href=\"?#{params}\">#{field.tr("_", " ").capitalize}</a></th>"
      end
      html << "</tr></thead><tbody>"

      # Table rows
      processed_hosts.each_with_index do |host, idx|
        html << "<tr><td>#{idx + 1}</td>"
        selected_fields.each do |field|
          value = host[field]? || ""
          cell = case field
          when "hostname"
            "<a href=\"/host/#{host["id"]}\">#{value}</a>"
          when "freemem_percent"
            klass = case (val = value.to_i)
                    when 0..20 then "critical"
                    when 21..40 then "warning"
                    else "healthy"
                    end
            "<span class=\"#{klass}\">#{value}%</span>"
          when "disk_max_used_percent"
            klass = case (val = value.to_i)
                    when 90..100 then "critical"
                    when 80..89 then "warning"
                    else "healthy"
                    end
            "<span class=\"#{klass}\" title=\"#{host["disk_max_used_string"]}\">#{value}%</span>"
          when "cpu_iowait_percent"
            klass = case (val = value.to_i)
                    when 10..100 then "critical"
                    when 2..9 then "warning"
                    else "healthy"
                    end
            "<span class=\"#{klass}\">#{value}%</span>"
          when "network_errors_per_sec"
            klass = value.to_i > 0 ? "critical" : "healthy"
            "<span class=\"#{klass}\">#{value}</span>"
          when "active_status"
            klass = value == "active" ? "healthy" : "critical"
            "<span class=\"#{klass}\">#{value}</span>"
          when "reboot_status"
            klass = value == "needs_reboot" ? "critical" : "healthy"
            "<span class=\"#{klass}\">#{value}</span>"
          else
            value
          end
          html << "<td>#{cell}</td>"
        end
        html << "</tr>"
      end
      html << "</tbody></table></body></html>"
    end

    env.response.content_type = "text/html"
    response
  end

end
