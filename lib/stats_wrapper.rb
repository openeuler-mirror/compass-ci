# SPDX-License-Identifier: GPL-2.0-only

# frozen_string_literal: true

LKP_SRC ||= ENV['LKP_SRC'] || '/c/lkp-tests'
require 'tempfile'
require 'English'
require_relative './dump_stat'
require_relative './json_logger.rb'

Dir[File.expand_path("#{LKP_SRC}/stats/*.rb")].uniq.each do |file|
  require file
end

PROGRAM_DIR = "#{LKP_SRC}/stats"

# exit processing the stats if the program is not in the program_list.
# program_list is a file that records all the programs(setups, monitors, tests,
# daemons) being executed during the test.
# this is to solve the problem for cluster test jobs running on the server node
# where no program's log file is generated for running server daemons but the
# stats processing for the program running on client node will also be handled
# on server node due to the current Job2sh algorithm.

# default stats are not in the program_list
module StatsWrapper
  def self.wrapper(program, program_time = nil)
    @program = program
    @stats_group = program_time || program
    @log = "#{RESULT_ROOT}/#{@stats_group}"

    return unless File.exist?("#{PROGRAM_DIR}/#{@program}")
    return unless File.exist?("#{@log}.yaml") || pretreatment
    return unless create_tmpfile

    check_tmpfile
    warn_empty_stats
    return unless create_stat

    check_empty_json
    delete_log_package
  end

  def self.wrapper_func(program, program_time = nil)
    @program = program
    @stats_group = program_time || program
    @log = "#{RESULT_ROOT}/#{@stats_group}"

    return unless File.exist?("#{@log}.yaml") || pretreatment

    if File.exist?("#{@log}.yaml")
      log_lines = read_log("#{@log}.yaml")
      stat_result = parse_simple_log_yaml(log_lines)
    else
      log_lines = read_log(@log)
      call_func_cmd = "#{@program.gsub('-', '_')}(log_lines)" # eg: proc_vmstats(log_lines)
      stat_result = eval(call_func_cmd)
    end
    return unless DumpStat.dump_stat(@stats_group, stat_result)

    check_empty_json
    delete_log_package
  end

  def self.pretreatment
    return unless available_program?
    return unless unzip_log

    extract_kmsg_dmesg
    check_incomplete_run(@log)
    check_soft_timeout
    return if check_empty_output
    #return if check_binary_output

    true
  end

  def self.available_program?
    yaml_data = File.read("#{LKP_SRC}/etc/default_stats.yaml")
    return true if yaml_data =~ /^#{@program}:/

    return unless File.exist?("#{RESULT_ROOT}/program_list")

    pro_list = File.read("#{RESULT_ROOT}/program_list")
    pro_list =~ /#{@program}/
  end

  def self.check_incomplete_run(file)
    return if File.size?(file)
    return unless File.exist?("#{LKP_SRC}/tests/#{@program}")

    data = "# missing #{@program} #{file}\nis_incomplete_run: 1"
    File.write("#{RESULT_ROOT}/last_state", data, mode: 'a')
  end

  def self.check_soft_timeout
    return unless File.exist?("#{RESULT_ROOT}/soft_timeout")

    last_state = File.readlines("#{RESULT_ROOT}/last_state")
    last_state.map!(&:chomp!)
    data = 'soft_timeout: 1'
    return if last_state.indlude?(data)

    File.write("#{RESULT_ROOT}/last_state", data, mode: 'a')
  end

  def self.delete_log
    File.delete(@log) if File.exist?(@log)
    File.delete("#{@log}.gz") if File.exist?("#{@log}.gz")
  end

  def self.check_empty_output
    return if File.size?(@log)
    return if %w[tcrypt kernel-size perf-profile].include?(@program)
    return if @program == 'dmesg' && File.size?("#{RESULT_ROOT}/kmsg")
    return if @program == 'kmsg' && File.size?("#{RESULT_ROOT}/dmesg")

    delete_log
    true
  end

  def self.check_binary_output
    return if %w[dmesg kmsg mpstat iostat].include?(@program)

    # kmsg may actually read the dmesg file
    # refer to the exception cases in check_empty_output()
    return unless File.exist?(@log)
    return unless File.read(@log) =~ /\x0\\/

    log_warn({
      'message' => "skip binary file #{@stats_group}",
      'error_message' => "skip binary file #{@log}"
    })

    true
  end

  def self.warn_empty_stats
    return if File.size?(@tmpfile)
    return if %w[dmesg ftrace turbostat perf-profile].include?(@program)
    return unless File.size?("#{RESULT_ROOT}/time")
    return if File.size?("#{RESULT_ROOT}/last_state")
    return if File.read("#{LKP_SRC}/etc/failure") =~ /^#{@program}\./
    return if File.read("#{LKP_SRC}/etc/pass") =~ /^#{@program}\./

    log_warn({
      'message' => "empty stats for #{@stats_group}",
      'error_message' => "empty stats for #{@log}"
    })
  end

  def self.check_exist_json
    return if File.exist?("#{RESULT_ROOT}/#{@stats_group}.json") || File.exist?("#{RESULT_ROOT}/#{@stats_group}.json.gz")
    return if File.exist?("#{RESULT_ROOT}/last_state") && File.read("#{RESULT_ROOT}/last_state") =~ /is_incomplete_run/
    return unless File.exist?("#{RESULT_ROOT}/stderr")

    log_warn({
      'message' => "no generate json file for #{@stats_group}",
      'error_message' => "no generate json file for #{@stats_group}, check #{RESULT_ROOT}"
    })
    data = "# no json file for #{@stats_group}\nis_incomplete_run: 1"
    File.write("#{RESULT_ROOT}/last_state", data, mode: 'a')
  end

  def self.check_empty_json
    testcase = RESULT_ROOT.split('/')[2]
    testcase[4, testcase.length] if testcase =~ /^kvm:/

    return if %w[borrow boot].include?(testcase)
    return unless File.exist?("#{RESULT_ROOT}/job.sh")

    # testcase maybe different with run_case
    # take fio-basic-1hdd-write.yaml job as example:
    # - testcase will be fio-basc
    # - run_case will be fio

    run_case = nil
    job_data = File.readlines("#{RESULT_ROOT}/job.sh")
    job_data.each do |line|
      next unless line.chomp! =~ %r{LKP_SRC/tests/wrapper}

      parse = line.split(' ')[-1]
      run_case = parse
      break
    end

    return unless run_case == @stats_group

    check_exist_json
  end

  def self.unzip_log
    if File.exist?("#{@log}.gz")
      return unless File.size?("#{@log}.gz")

      system "zcat #{@log}.gz > #{@log}"
    elsif File.exist?("#{@log}.xz")
      return unless File.size?("#{@log}.xz")

      system "xzcat #{@log}.xz > #{@log}"
    end

    true
  end

  def self.extract_kmsg_dmesg
    @kmsg_log = "#{RESULT_ROOT}/kmsg"
    # extract kmsg for kmsg related stats
    if @log =~ %r{^#{RESULT_ROOT}/(boot-memory|boot-time|tcrypt|dmesg)$}
      system "xzcat #{@kmsg_log}.xz" if File.exist?("#{@kmsg_log}.xz")
    end

    @dmesg_log = "#{RESULT_ROOT}/dmesg"
    # extract dmesg for dmesg related stats
    return unless @log =~ %r{^#{RESULT_ROOT}/kmsg$}

    system "xzcat #{@dmesg_log}.xz > #{@dmesg_log}" if File.exist?("#{@dmesg_log}.xz")
  end

  def self.create_yaml_tmpfile(file)
    File.readlines(file).each do |line|
      next if line =~ /{|}/

      line.lstrip!
      File.write(@tmpfile, line, mode: 'a')
    end
  end

  def self.create_tmpfile
    tmp = Tempfile.new('lkp-stats.', '/tmp')
    @tmpfile = tmp.path
    create_status = true
    if File.exist?(@log)
      %x(#{PROGRAM_DIR}/#{@program} #{@log} < #{@log} > #{@tmpfile})
      unless $CHILD_STATUS.exitstatus.zero?
        log_error({
          'message' => "#{PROGRAM_DIR}/#{@program} exit code #{$CHILD_STATUS.exitstatus}",
          'error_message' => "#{PROGRAM_DIR}/#{@program} #{@log} < #{@log} exit code #{$CHILD_STATUS.exitstatus}, check #{@tmpfile} or #{RESULT_ROOT}/#{@program}"
        })
        create_status = false
      end
    elsif File.exist?("#{@log}.yaml")
      create_yaml_tmpfile("#{@log}.yaml")
    else
      %x(#{PROGRAM_DIR}/#{@program} < /dev/null > #{@tmpfile})
      unless $CHILD_STATUS.exitstatus.zero?
        log_error({
          'message' => "#{PROGRAM_DIR}/#{@program} exit code #{$CHILD_STATUS.exitstatus}",
          'error_message' => "#{PROGRAM_DIR}/#{@program} < /dev/null exit code #{$CHILD_STATUS.exitstatus}, check #{@tmpfile} or #{RESULT_ROOT}/#{@program}"
        })
        create_status = false
      end
    end

    create_status
  end

  def self.check_tmpfile
    str = File.read("#{LKP_SRC}/etc/failure")
    str += File.read("#{LKP_SRC}/etc/pass")

    str =~ /^#{@program}\./ || check_incomplete_run(@tmpfile)
  end

  def self.dump_stat(stats_group, file)
    %x(#{LKP_SRC}/sbin/dump-stat #{stats_group} < #{file})
    unless $CHILD_STATUS.exitstatus.zero?
      log_error({
        'message' => "#{LKP_SRC}/sbin/dump-stat #{@program} exit code #{$CHILD_STATUS.exitstatus}",
        'error_message' => "#{LKP_SRC}/sbin/dump-stat #{@program} exit code #{$CHILD_STATUS.exitstatus}, check #{file} or #{RESULT_ROOT}/#{stats_group}"
      })
      return nil
    end

    File.delete(file)

    true
  end

  def self.create_stat
    if @program == 'ftrace'
      Dir.foreach(RESULT_ROOT) do |file|
        if file =~ /^#{@program}\..*\.yaml/
          stats_group = File.basename(file, '.yaml')
          dump_stat(stats_group, file)
        end
      end
    else
      dump_stat(@stats_group, @tmpfile)
    end
  end

  def self.delete_log_package
    if File.exist?("#{@log}.gz")
      File.delete(@log)
    elsif File.exist?("#{@log}.xz")
      File.delete(@log)
    end

    # delete temporarily extracted kmsg above
    File.delete(@kmsg_log) if File.exist?("#{@kmsg_log}.xz")

    # delete temporarily extracted dmesg above
    File.delete(@dmesg_log) if File.exist?("#{@dmesg_log}.xz")

    File.delete(@tmpfile) if @tmpfile && File.exist?(@tmpfile)
  end
end

# read line of log
# return Array(String)
def read_log(log_path)
  return nil unless File.exist?(log_path)

  File.readlines(log_path)
end

def parse_simple_log_yaml(log_lines)
  result = Hash.new { |hash, key| hash[key] = [] }
  log_lines.each do |line|
    key, value = line.split(/:?\s+/)
    result[key] << value
  end

  result
end
