require 'json'
require_relative './es_query.rb'
require_relative './params_group'

def get_install_rpm_result_by_group_id(group_id)
  es = ESQuery.new 
  job_list = es.multi_field_query({'group_id' => group_id})['hits']['hits']
  job_list.map! do |job|
    if job_is_useful?(job)
      job['_source']['stats']
    end
  end

  job_list.compact
end

def parse_install_rpm_result_to_json(result_list)
  tmp_hash = {}
  result_list.each do |result|
    result.each do |k, v|
      case k
        # install-rpm.CUnit_rpm_full_name.CUnit-2.1.3.aarch64
        when /install-rpm\.(.*)_rpm_full_name\.(.*)/
          tmp_hash[$1] = {} unless tmp_hash.has_key?($1)
          tmp_hash[$1].merge!({"rpm_full_name" => $2})
        # install-rpm.CUnit_rpm_src_name.CUnit-2.1.3-21.oe1.src.rpm 
        when /install-rpm\.(.*)_rpm_src_name\.(.*)/
          tmp_hash[$1] = {} unless tmp_hash.has_key?($1)
          tmp_hash[$1].merge!({"rpm_src_name" => $2})
        # install-rpm.docker-engine_install.pass
        when /install-rpm\.(.*)_install\.(.*)/
          tmp_hash[$1] = {} unless tmp_hash.has_key?($1)
          tmp_hash[$1].merge!({"install" => $2})
        # install-rpm.docker-engine-18.09.0-101.oe1.aarch64_uninstall.pass
        when /install-rpm\.(.*)_uninstall\.(.*)/
          tmp_hash[$1] = {} unless tmp_hash.has_key?($1)
          tmp_hash[$1].merge!({"uninstall" => $2})
        # install-rpm.docker-engine-18.09.0-101.oe1.aarch64_group_.Tools/Docker
        when /install-rpm\.(.*)_group_\.(.*)/
          tmp_hash[$1] = {} unless tmp_hash.has_key?($1)
          tmp_hash[$1].merge!({"group" => $2})
        # install-rpm.docker-engine-18.09.0-101.oe1.aarch64_libs_.true
        when /install-rpm\.(.*)_libs_\.(.*)/
          tmp_hash[$1] = {} unless tmp_hash.has_key?($1)
          tmp_hash[$1].merge!({"libs" => $2})
        # install-rpm.docker-engine-18.09.0-101.oe1.aarch64_cmd_/usr/bin/docker.pass
        when /install-rpm\.(.*)_cmd_(.*)\.(.*)/
          tmp_hash[$1] = {} unless tmp_hash.has_key?($1)
          tmp_hash[$1]['cmds'] = {} unless tmp_hash[$1].has_key?('cmds')
          tmp_hash[$1]['cmds'].merge!({$2 => $3})
        # install-rpm.docker-engine-18.09.0-101.oe1.aarch64_service_docker.service_stop.pass
        when /install-rpm\.(.*)_service_(.*)\.(.*)/
          tmp_hash[$1] = {} unless tmp_hash.has_key?($1)
          tmp_hash[$1]['services'] = {} unless tmp_hash[$1].has_key?('services')
          tmp_hash[$1]['services'].merge!({$2 => $3})
        end
    end
  end

  tmp_hash
end
