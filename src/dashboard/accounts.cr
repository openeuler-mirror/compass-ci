class Sched

  # Helper function to generate the common headline and tab line
  private def generate_common_headline(active_tab : String) : String
    String.build do |html|
      html << <<-HTML
        <!DOCTYPE html>
        <html>
        <head>
          <title>Compass CI Dashboard</title>
          <meta http-equiv="refresh" content="600">
          <link href="https://fonts.googleapis.com/css2?family=Roboto+Mono:wght@300;400;500&family=Roboto:wght@300;400;500&display=swap" rel="stylesheet">
          <style>
            :root { font-family: 'Roboto', sans-serif; }
            code, .mono { font-family: 'Roboto Mono', monospace; }
            body { margin: 2rem; background: #f0f4f8; }
            .tab-container { display: flex; gap: 1rem; margin-bottom: 2rem; }
            .tab { padding: 0.5rem 1rem; border-radius: 4px; background: #3498db; color: white; text-decoration: none; }
            .tab.active { background: #1c5980; }
            .tab:hover { background: #1c5980; }
            .filter-container { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1rem; }
            .filter-group { background: white; padding: 1rem; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.12); }
            table { background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.12); margin-top: 2rem; }
            th { background: #f7cac9; color: white; padding: 0.3rem; }
            td { padding: 0.5rem; border-bottom: 1px solid #ecf0f1; }
            tr:hover { background: #f8f9fa; }
            a { color: #3498db; text-decoration: none; }
            a:hover { text-decoration: underline; }
          </style>
        </head>
        <body>
          <h1>Compass CI Dashboard</h1>
          <div class="tab-container">
      HTML

      # Define tabs
      tabs = [
        {name: "Hosts",           path: "/scheduler/v1/dashboard/hosts"},
        {name: "Submit Jobs",     path: "/scheduler/v1/dashboard/jobs/pending"},
        {name: "Running Jobs",    path: "/scheduler/v1/dashboard/jobs/running"},
        {name: "Accounts",        path: "/scheduler/v1/dashboard/accounts"},
      ]

      # Render tabs
      tabs.each do |tab|
        active_class = tab[:name].downcase.gsub(' ', '-') == active_tab ? "active" : ""
        html << "<a href=\"#{tab[:path]}\" class=\"tab #{active_class}\">#{tab[:name]}</a>"
      end

      html << <<-HTML
          </div>
      HTML
    end
  end

  def api_dashboard_accounts(env)
    # Filter parameters
    selected_gitee_ids = env.params.query.fetch_all("gitee_id")
    selected_my_accounts = env.params.query.fetch_all("my_account")
    selected_my_emails = env.params.query.fetch_all("my_email")
    selected_my_names = env.params.query.fetch_all("my_name")

    # Sort parameters
    sort_field = env.params.query["sort"]? || "my_account"
    sort_order = env.params.query["order"]? || "asc"

    # Field selection
    selected_fields = env.params.query["fields"]?.try(&.split(',')) || %w[
      gitee_id
      my_account
      my_email
      my_name
      weight
    ]

    output_format = env.params.query["output"]? || "html"

    # Filter accounts
    filtered_accounts = @accounts_cache.accounts.select do |_, account|
      (selected_gitee_ids.empty? || selected_gitee_ids.includes?(account.gitee_id)) &&
      (selected_my_accounts.empty? || selected_my_accounts.includes?(account.my_account)) &&
      (selected_my_emails.empty? || selected_my_emails.includes?(account.my_email)) &&
      (selected_my_names.empty? || selected_my_names.includes?(account.my_name))
    end

    # Sort accounts
    sorted_accounts = filtered_accounts.values.sort_by! do |account|
      case sort_field
      when "gitee_id" then account.gitee_id
      when "my_account" then account.my_account
      when "my_email" then account.my_email
      when "my_name" then account.my_name
      when "weight" then account.weight.to_s
      else ""
      end
    end
    sorted_accounts.reverse! if sort_order == "desc"

    # Process accounts into uniform hashes
    processed_accounts = sorted_accounts.map do |account|
      {
        "gitee_id" => account.gitee_id,
        "my_account" => account.my_account,
        "my_email" => account.my_email,
        "my_name" => account.my_name,
        "weight" => account.weight.to_s,
      }
    end

    # Generate output based on the format
    if output_format == "text"
      env.response.content_type = "text/plain"
      return generate_plain_text_table(processed_accounts, selected_fields)
    end

    # Build HTML with modern styling
    response = String.build do |html|
      html << generate_common_headline("accounts")

      # Table rendering
      html << "<table><thead><tr><th>#</th>"
      selected_fields.each do |field|
        current_order = sort_field == field ? (sort_order == "asc" ? "desc" : "asc") : "asc"
        params = HTTP::Params.build do |form|
          env.params.query.each { |k, vs| vs.split(",").each { |v| form.add(k, v) unless k == "sort" || k == "order" } }
          form.add("sort", field)
          form.add("order", current_order)
        end
        html << "<th><a href=\"?#{params}\">#{field}</a></th>"
      end
      html << "</tr></thead><tbody>"

      processed_accounts.each_with_index do |account, idx|
        html << "<tr><td>#{idx + 1}</td>"
        selected_fields.each do |field|
          value = account[field]? || ""
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
