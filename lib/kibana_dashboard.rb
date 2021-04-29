# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

CCI_SRC = ENV['CCI_SRC'] || File.dirname(File.dirname(File.realpath($PROGRAM_NAME)))

require_relative 'constants.rb'

# operat the kibana dashboards
class KibanaDashboard
  def initialize(host = KIBANA_HOST, port = KIBANA_PORT, user = ES_USER, password = ES_PASSWORD)
    @port = port
    @profix = "curl -u #{user}:#{password}"
    @profix += " http://#{host}:#{port}/api/kibana/dashboards/"
  end

  def get_default_ids(dashboard_ids)
    return dashboard_ids unless dashboard_ids.empty?

    return %w[data resource all] if @port == KIBANA_PORT
    return %w[data all] if @port == LOGGING_KIBANA_PORT

    dashboard_ids
  end

  def get_default_files(files)
    return files unless files.empty?

    files = []
    tmp = []
    profix = nil

    if @port == KIBANA_PORT
      profix = CCI_SRC + '/container/kibana/'
      tmp = %w[data.json resource.json all.json]
    elsif @port == LOGGING_KIBANA_PORT
      profix = CCI_SRC + '/container/logging-kibana/'
      tmp = %w[data.json all.json]
    end

    tmp.each do |f|
      files << profix + f
    end

    files
  end

  def export(dashboard_ids)
    dashboard_ids = get_default_ids(dashboard_ids)
    raise 'empty dashboard ids' if dashboard_ids.empty?

    profix = @profix + 'export?dashboard='
    dashboard_ids.each do |id|
      cmd = profix + "#{id} >> #{id}.json"
      puts cmd
      system cmd
    end
  end

  def import(files)
    files = get_default_files(files)
    raise 'empty json files' if files.empty?

    profix = @profix + 'import'
    profix += " -H 'Content-Type: application/json' -H 'kbn-xsrf: reporting'"
    files.each do |f|
      cmd = profix + " -d @#{f}"
      puts cmd
      system cmd
    end
  end
end
