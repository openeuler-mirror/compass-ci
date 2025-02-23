class Sched

  def get_job_plain_number(job, field) : Int32
    job.hash_plain.has_key?(field) ? job.hash_plain[field].to_i32 : 0
  end

  def api_dashboard_jobs(env)
    # Filter parameters
    selected_my_accounts = env.params.query.fetch_all("my_account")
    selected_suites = env.params.query.fetch_all("suite")
    selected_categories = env.params.query.fetch_all("category")
    selected_osv = env.params.query.fetch_all("osv")
    selected_arch = env.params.query.fetch_all("arch")
    selected_testbox = env.params.query.fetch_all("testbox")
    selected_job_stage = env.params.query.fetch_all("job_stage")

    # Sort parameters
    sort_field = env.params.query["sort"]? || "submit_date"
    sort_order = env.params.query["order"]? || "asc"

    # Field selection
    selected_fields = env.params.query["fields"]?.try(&.split(',')) || %w[
      my_account
      submit_date
      suite
      category
      osv
      arch
      testbox
      job_stage
      boot_time
      timeout_seconds
    ]

    # Field display names
    field_display_name = {
      "my_account"          => "Account",
      "submit_date"         => "Submit Date",
      "suite"               => "Suite",
      "category"            => "Category",
      "osv"                 => "OS Version",
      "arch"                => "Arch",
      "testbox"             => "Testbox",
      "job_stage"           => "Job Stage",
      "boot_time"           => "Boot Time",
      "timeout_seconds"     => "Timeout",
    }

    output_format = env.params.query["output"]? || "html"

    # Filter jobs
    jobs_cache = env.request.path.ends_with?("submit-jobs") ? @jobs_cache_in_submit : @jobs_cache
    filtered_jobs = jobs_cache.select do |_, job|
      (selected_my_accounts.empty? || selected_my_accounts.includes?(job.my_account)) &&
      (selected_suites.empty? || selected_suites.includes?(job.suite? || "N/A")) &&
      (selected_categories.empty? || selected_categories.includes?(job.category? || "N/A")) &&
      (selected_osv.empty? || selected_osv.includes?(job.osv)) &&
      (selected_arch.empty? || selected_arch.includes?(job.arch)) &&
      (selected_testbox.empty? || selected_testbox.includes?(job.testbox)) &&
      (selected_job_stage.empty? || selected_job_stage.includes?(job.job_stage))
    end

    # Sort jobs
    if ["timeout_seconds"].includes? sort_field
      sorted_jobs = filtered_jobs.values.sort_by! do |job|
        case sort_field
        when "timeout_seconds" then job.timeout_seconds? || 0
        else
          0
        end
      end
    else
      sorted_jobs = filtered_jobs.values.sort_by! do |job|
        job.hash_plain[sort_field]? || ""
      end
    end
    sorted_jobs.reverse! if sort_order == "desc"

    # Process jobs into uniform hashes
    processed_jobs = sorted_jobs.map do |job|
      {
        "my_account"            => job.my_account,
        "submit_date"           => job.submit_date,
        "suite"                 => job.suite? || "",
        "category"              => job.category? || "",
        "osv"                   => job.osv,
        "arch"                  => job.arch,
        "testbox"               => job.testbox,
        "job_stage"             => job.job_stage,
        "boot_time"             => job.boot_time? || "",
        "timeout_seconds"       => ui_format_time((job.timeout_seconds? || 0) // 60),
      }
    end

    # Generate output based on the format
    if output_format == "text"
      env.response.content_type = "text/plain"
      return generate_plain_text_table(processed_jobs, selected_fields)
    end

    # Build HTML with modern styling
    response = String.build do |html|
      # Determine if this is for submit-jobs or running-jobs
      active_tab = env.request.path.ends_with?("submit-jobs") ? "submit-jobs" : "running-jobs"

      # Generate common headline with the appropriate active tab
      html << generate_common_headline(active_tab)
      html << <<-HTML
          <form method="get">
            <div class="filter-container">
      HTML

      # Unified filter rendering
      filters = [
        {
          type:        :checkbox_group,
          name:        "my_account",
          title:       "Accounts",
          options:     processed_jobs.map { |job| job["my_account"] }.tally,
          selected:    selected_my_accounts,
        },
        {
          type:        :checkbox_group,
          name:        "suite",
          title:       "Suites",
          options:     processed_jobs.map { |job| job["suite"] }.tally,
          selected:    selected_suites,
        },
        {
          type:        :checkbox_group,
          name:        "category",
          title:       "Categories",
          options:     processed_jobs.map { |job| job["category"] }.tally,
          selected:    selected_categories,
        },
        {
          type:        :checkbox_group,
          name:        "osv",
          title:       "OS Versions",
          options:     processed_jobs.map { |job| job["osv"] }.tally,
          selected:    selected_osv,
        },
        {
          type:        :checkbox_group,
          name:        "arch",
          title:       "Architectures",
          options:     processed_jobs.map { |job| job["arch"] }.tally,
          selected:    selected_arch,
        },
        {
          type:        :checkbox_group,
          name:        "testbox",
          title:       "Testboxes",
          options:     processed_jobs.map { |job| job["testbox"] }.tally,
          selected:    selected_testbox,
        },
        {
          type:        :checkbox_group,
          name:        "job_stage",
          title:       "Job Stages",
          options:     processed_jobs.map { |job| job["job_stage"] }.tally,
          selected:    selected_job_stage,
        },
      ]

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
        end
        html << "</div>"
      end

      html << <<-HTML
            </div>
            <button type="submit" style="margin-top: 1rem; padding: 8px 16px; background: #3498db; color: white; border: 1px; border-radius: 4px;">Apply Filters</button>
          </form>
      HTML

      # Table rendering
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

      processed_jobs.each_with_index do |job, idx|
        html << "<tr><td>#{idx + 1}</td>"
        selected_fields.each do |field|
          value = job[field]? || ""
          html << "<td>#{value}</td>"
        end
        html << "</tr>"
      end

      html << "</tbody></table></body></html>"
    end

    env.response.content_type = "text/html"
    response
  end

end
