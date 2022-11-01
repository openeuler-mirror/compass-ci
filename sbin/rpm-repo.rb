#!/usr/bin/ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'set'
require 'clockwork'
require_relative '../lib/mq_client'
require_relative '../lib/json_logger.rb'
require_relative '../lib/config_account'
require_relative "#{ENV['LKP_SRC']}/lib/do_local_pack"
require_relative '../lib/parse_install_rpm'
require_relative './build-compat-list'
require_relative '../lib/es_query.rb'
require_relative '../lib/constants.rb'

MQ_HOST = ENV['MQ_HOST'] || ENV['LKP_SERVER'] || '172.17.0.1'
MQ_PORT = ENV['MQ_PORT'] || 5672
PREFETCH_COUNT = 1

# ---------------------------------------------------------------------------------------------------------------------------------------
# end_user can use cmd:
#  curl -H 'Content-Type: Application/json' -XPOST 'localhost:10003/upload' \
#  -d '{"upload_rpms": ["/srv/rpm/upload/openeuler-20.03-LTS/compat-centos8/centos-appstream/aarch64/Packages/*.rpm"]}'
#
# the post data would be stored in mq queue "update_repo" through update-repo service
# ---------------------------------------------------------------------------------------------------------------------------------------
#
# HandleRepo used to handle the mq queue "update_repo"
#
# Example items in @update_repo_mq.queue "update_repo": { "upload_rpms" => ["/srv/rpm/upload/**/Packages/*.rpm", "/srv/rpm/upload/**/source/*.rpm"], "job_id": "xxx"}
# handle_new_rpm
#    move /srv/rpm/upload/**/*.rpm to /srv/rpm/testing/**/*.rpm
#    update /srv/rpm/testing/**/repodata
# update_pub_dir
#    copy /srv/rpm/testing/**/*.rpm to /srv/rpm/pub/**/*.rpm
#    change /srv/rpm/pub/**/repodata
# @update_repo_mq.ack(info)
class HandleRepo
  @@upload_dir_prefix = '/srv/rpm/upload/'
  def initialize
    @es = ESQuery.new(ES_HOSTS)
    @update_repo_mq = MQClient.new(hostname: MQ_HOST, port: MQ_PORT, prefetch_count: PREFETCH_COUNT)
    @create_repodata_mq = MQClient.new(hostname: MQ_HOST, port: MQ_PORT, prefetch_count: PREFETCH_COUNT)
    @createrepodata_complete_mq = MQClient.new(hostname: MQ_HOST, port: MQ_PORT, prefetch_count: PREFETCH_COUNT)
    @log = JSONLogger.new
  end

  @@upload_flag = true
  @@create_repo_path = Set.new
  @@create_repodata = false
  def handle_new_rpm
    update_repo_queue = @update_repo_mq.queue('update_repo')
    createrepodata_queue = @create_repodata_mq.queue('createrepodata')
    Thread.new 10 do
      update_repo_queue.subscribe({ block: true, manual_ack: true }) do |info, _pro, msg|
        loop do
          next unless @@upload_flag

          begin
            rpm_info = JSON.parse(msg)
            check_upload_rpms(rpm_info)
            handle_upload_rpms(rpm_info)

            @@create_repodata = false
            createrepodata_queue.publish(msg)
            @update_repo_mq.ack(info)
            break
          rescue StandardError => e
            @log.warn({
              "handle_new_rpm error message": e.message
            }.to_json)
            @update_repo_mq.ack(info)
            break
          end
        end
      end
    end
  end

  def handle_upload_rpms(rpm_info)
    rpm_info['upload_rpms'].each do |rpm|
      rpm_path = File.dirname(rpm).sub('upload', 'testing')
      dest = File.join(rpm_path.to_s, File.basename(rpm))
      extras_rpm_path = create_extras_path(rpm)

      unless check_if_extras(rpm)
        FileUtils.mkdir_p(rpm_path) unless File.directory?(rpm_path)
        @@create_repo_path << rpm_path
        FileUtils.mv(rpm, dest)
      end

      FileUtils.mkdir_p(extras_rpm_path) unless File.directory?(extras_rpm_path)
      @@create_repo_path << File.dirname(extras_rpm_path)

      extras_dest = File.join(extras_rpm_path.to_s, File.basename(rpm))
      unless check_if_extras(rpm)
        system("ln -f #{dest} #{extras_dest}")
      else
        FileUtils.mv(rpm, extras_dest)
      end
    end
  end

  def check_if_extras(rpm)
    rpm_list = rpm.split('/')
    if rpm.split('/')[5] == "refreshing" && rpm.split('/')[6] == "extras"
      return true
    elsif rpm.split('/')[5] == "extras"
      return true
    else
      return false
    end
  end

  def create_extras_path(rpm)
    rpm_path = File.dirname(rpm).sub('upload', 'testing')
    extras_rpm_path = ""
    if rpm.split('/')[5] == "refreshing"
      extras_rpm_path_prefix = rpm_path.split('/')[0..4].join('/') + "/refreshing/extras/"
    else
      extras_rpm_path_prefix = rpm_path.split('/')[0..4].join('/') + "/extras/"
    end

    extras_rpm_path_suffix = rpm_path.split('/')[-2..-1].join('/') + "/" + "#{File.basename(rpm)[0].downcase}"
    extras_rpm_path = extras_rpm_path_prefix + extras_rpm_path_suffix
  end

  def get_results_by_group_id(group_id)
    query = { 'group_id' => group_id }
    tmp_stats_hash = get_install_rpm_result_by_group_id(query)
    stats_hash = parse_install_rpm_result_to_json(tmp_stats_hash)
    refine_json(stats_hash)
  end

  def get_srpm_addr(job_id)
    result_hash = {}
    query_result = @es.query_by_id(job_id)
    rpmbuild_job_id = query_result['rpmbuild_job_id']
    rpmbuild_query_result = @es.query_by_id(rpmbuild_job_id)
    result_hash['srpm_addr'] = rpmbuild_query_result['repo_addr'] || rpmbuild_query_result['upstream_repo']
    result_hash['rpmbuild_result_url'] = "https://api.compass-ci.openeuler.org#{rpmbuild_query_result['result_root']}"
    result_hash['repo_name'] = rpmbuild_query_result['custom_repo_name'] || rpmbuild_query_result['rpmbuild']['custom_repo_name']
    result_hash
  end

  def update_compat_software_list(pkg_info)
    query = {
      'query' => {
        'query_string' => {
          'query' => "softwareName:#{pkg_info['softwareName']}"
        }
      }
    }.to_json

    if pkg_info['repo_name'].start_with?("refreshing")
      pkg_info['repo_name'] = pkg_info['repo_name'].delete_prefix('refreshing/')
      pkg_info['repo_name'] = "extras" if pkg_info['repo'] == "extras"
      update_compat_software?('srpm-info-tmp', query, pkg_info)
    else
      pkg_info['repo_name'] = "extras" if pkg_info['repo'] == "extras"
      update_compat_software?('srpm-info', query, pkg_info)
    end
  end

  def deal_pub_dir(group_id)
    result_list = get_results_by_group_id(group_id)
    update = []
    result_list.each do |pkg_info|
      next unless pkg_info['install'] == 'pass'
      next unless pkg_info['downloadLink']
      next unless pkg_info['src_location']
      next unless pkg_info['result_root']

      job_id = pkg_info['result_root'].split('/')[-1]
      h = get_srpm_addr(job_id)
      next if h.empty?()
      pkg_info.merge!(get_srpm_addr(job_id))

      update_compat_software_list(pkg_info)

      rpm_path = pkg_info['downloadLink'].delete_prefix!('https://api.compass-ci.openeuler.org:20018')
      srpm_path = pkg_info['src_location'].delete_prefix!('https://api.compass-ci.openeuler.org:20018')

      location = '/srv' + rpm_path
      src_location = '/srv' + srpm_path
      update << location
      update << src_location
    end
    update_pub_dir(update)
  end

  def check_upload_rpms(data)
    raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'no upload_rpms params' }) unless data.key?('upload_rpms')
    raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'no job_id params' }) unless data.key?('job_id')
    raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'upload_rpms params type error' }) if data['upload_rpms'].class != Array

    data['upload_rpms'].each do |rpm|
      raise JSON.dump({ 'errcode' => '200', 'errmsg' => "no custom_repo_name specified", 'job_id' => "#{data['job_id']}" }) if rpm.split('/')[5] == ""
      raise JSON.dump({ 'errcode' => '200', 'errmsg' => "#{rpm} not exist", 'job_id' => "#{data['job_id']}" }) unless File.exist?(rpm)
      raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'the upload directory is incorrect', 'job_id' => "#{data['job_id']}" }) unless File.dirname(rpm).start_with?(@@upload_dir_prefix)
    end
  end

  def update_pub_dir(update)
    pub_path_list = Set.new
    update.each do |rpm|
      if rpm.split('/')[5] == "refreshing"
        pub_path = File.dirname(rpm).sub('testing', 'tmp_pub')
      else
        pub_path = File.dirname(rpm).sub('testing', 'pub')
      end
      FileUtils.mkdir_p(pub_path) unless File.directory?(pub_path)

      dest = File.join(pub_path, File.basename(rpm))
      next unless File.exist?(rpm)
      system("ln -f #{rpm} #{dest}")
      if File.basename(pub_path) != "Packages"
        pub_path_list << File.dirname(pub_path)
      else
        pub_path_list << pub_path
      end
    end

    pub_path_list.each do |pub_path|
        if File.basename(pub_path) != "Packages"
          pub_path = File.dirname(pub_path)
        end
      system("createrepo --update $(dirname #{pub_path})")
    end
  end

  def ack_create_repo_done
    createrepodata_queue = @create_repodata_mq.queue('createrepodata')
    createrepodata_complete_queue = @createrepodata_complete_mq.queue('createrepodata_complete')
    Thread.new do
      createrepodata_queue.subscribe({ manual_ack: true }) do |info, _pro, msg|
        loop do
          begin
            next unless @@create_repodata
            @create_repodata_mq.ack(info)
            createrepodata_complete_queue.publish(msg)
            break
          rescue StandardError => e
            @log.warn({
              "create_repodata error message": e.message
            }.to_json)
            @create_repodata_mq.ack(info)
            break
          end
        end
      end
    end
  end


  # @@create_repo_path:
  # Example items in @@create_repo_path:
  #      "/srv/rpm/testing/**/Packages"
  #      "/srv/rpm/testing/$os_version/extras/$arch/Packages/a-z"
  # if @@create_repo_path is not empty
  #     update the repodata for the repo_path in the @@create_repo_path
  #
  # @@upload_flag:
  # The initial value of @@upload_flag is true.
  # when the repo is being update repodata, Packages are not allowed be moved to the repo.
  # So, we use this @@upload_flag as a lock to control the movement of the packages.
  #
  # @@create_repodata:
  # The initial value of @@create_repodata is false.
  # we have to ensure that the packages have moved to "/srv/rpm/testing" from "/srv/rpm/upload",
  # and the "/srv/rpm/testing/xxx" repodata already updated, then, the data in the createrepodata_queue
  # can be published to createrepodata_complete_queue, and the install-rpm task can be submitted.
  # Therefore, we will set the value of @@create_repodata to control the sync execution of the entire process.
  def create_repo
    createrepodata_queue = @create_repodata_mq.queue('createrepodata')
    Thread.new do
      loop do
        begin
          sleep 180
          next if @@create_repo_path.empty?

          @@upload_flag = false
          # Avoid mv in handle_new_rpm() is not over.
          sleep 1

          threads = {}
          @@create_repo_path.each do |path|
            thr = Thread.new do
              if File.basename(path) != "Packages"
                path = File.dirname(path)
              end
              system("createrepo --update $(dirname #{path})")
            end
            threads[path] = thr
          end

          threads.each do |_, thr|
            thr.join
          end

          @@create_repodata = true
          sleep 5
          while true
            unless createrepodata_queue.message_count == 0
              sleep 1
            else
              break
            end
          end

        rescue StandardError => e
          @log.warn({
            "create_repodata error message": e.message
          }.to_json)
        end
        @@create_repo_path.clear
        @@upload_flag = true
      end
    end
  end

  def extras_parse_arg(rpm)
    extras_submit_argv = ["#{ENV['LKP_SRC']}/sbin/submit", "--no-pack"]
    extras_rpm_path = create_extras_path(rpm)
    extras_rpm_path = File.dirname(File.dirname(extras_rpm_path))
    extras_rpm_path.sub!('/srv', '')
    mount_repo_name = "extras"
    extras_rpm_path = "https://api.compass-ci.openeuler.org:20018#{extras_rpm_path}"

    extras_submit_argv.push("mount_repo_addr=#{extras_rpm_path}")
    extras_submit_argv.push("mount_repo_name=#{mount_repo_name}")
    extras_submit_argv
  end

  def rpmbuild_arg(job_id)
    rpmbuild_argv = []
    query_result = @es.query_by_id(job_id)

    upstream_repo = query_result['upstream_repo']
    upstream_commit = query_result['upstream_commit']
    if ! upstream_repo.nil?  && upstream_repo.start_with?('https://gitee.com/src-oepkgs/') && ! upstream_commit.nil?
      rpmbuild_argv.push("upstream_repo=#{upstream_repo}")
      rpmbuild_argv.push("upstream_commit=#{upstream_commit}")
      rpmbuild_argv.push("-i /c/lkp-tests/jobs/secrets_info.yaml")
    end
    rpmbuild_argv.push("os=#{query_result['os']}")
    rpmbuild_argv.push("os_version=#{query_result['os_version']}")
    rpmbuild_argv.push("testbox=#{query_result['tbox_group']}")
    rpmbuild_argv.push("queue=#{query_result['queue']}")
    rpmbuild_argv.push("rpmbuild_job_id=#{job_id}")
    rpmbuild_argv.push("docker_image=#{query_result['docker_image']}") if query_result.key?('docker_image')
    rpmbuild_argv
  end


  # input:
  #    rpm: /srv/rpm/upload/**/Packages/*.rpm
  #    job_id: the job id of rpmbuild task
  # return:
  #    extras_submit_argv: ["#{ENV['LKP_SRC']}/sbin/submit", "--no-pack", "install-rpm.yaml", "arch=aarch64", "xxx"]
  #    submit_argv: ["#{ENV['LKP_SRC']}/sbin/submit", "--no-pack", "install-rpm.yaml", "arch=aarch64", "xxx"]
  def parse_arg(rpm, job_id)
    extras_submit_argv = extras_parse_arg(rpm)
    rpmbuild_argv = rpmbuild_arg(job_id)
    extras_submit_argv = extras_submit_argv + rpmbuild_argv

    submit_argv = ["#{ENV['LKP_SRC']}/sbin/submit", "--no-pack"]
    rpm_path = File.dirname(rpm).sub('upload', 'testing')
    rpm_path.sub!('/srv', '')
    rpm_path = "https://api.compass-ci.openeuler.org:20018#{rpm_path}"
    rpm_path = rpm_path.delete_suffix('/Packages')
    submit_arch = rpm_path.split('/')[-1]

    fixed_arg = YAML.load_file('/etc/submit_arg.yaml')
    unless check_if_extras(rpm)
     mount_repo_name = rpm_path.split('/')[4..-3].join('/')
     submit_argv.push("arch=#{submit_arch}")
     submit_argv.push("mount_repo_name=#{mount_repo_name}")
     submit_argv.push("mount_repo_addr=#{rpm_path}")
     submit_argv = submit_argv + rpmbuild_argv
     submit_argv.push((fixed_arg['yaml']).to_s)
    end
    extras_submit_argv.push("arch=#{submit_arch}")

    extras_submit_argv.push((fixed_arg['yaml']).to_s)

    return submit_argv, extras_submit_argv, submit_arch
  end


  # input:
  #    rpm_info: { "upload_rpms" => ["/srv/rpm/upload/**/Packages/*.rpm", "/srv/rpm/upload/**/source/*.rpm"], "job_id": "xxxx"}
  # return:
  #    real_argvs: ["#{ENV['LKP_SRC']}/sbin/submit", "--no-pack", "install-rpm.yaml", "arch=aarch64", "xxx"]
  #    extras_real_argvs: ["#{ENV['LKP_SRC']}/sbin/submit", "--no-pack", "install-rpm.yaml", "arch=aarch64", "xxx"]
  def parse_real_argvs(rpm_info)
    group_id = Time.new.strftime('%Y-%m-%d') + '-auto-install-rpm'
    job_id = rpm_info['job_id']
    rpm_names = []
    real_argvs = []
    extras_real_argvs = []
    rpm_info['upload_rpms'].each do |rpm|
      submit_argv, extras_submit_argv, submit_arch = parse_arg(rpm, job_id)
      next if submit_arch == 'source'

      # zziplib-0.13.62-12.aarch64.rpm => zziplib-0.13.62-12.aarch64
      # zziplib-help.rpm
      # zziplib-doc.rpm
      rpm_name = File.basename(rpm).delete_suffix('.rpm')
      rpm_names << rpm_name
      real_argvs = Array.new(submit_argv)
      extras_real_argvs = Array.new(extras_submit_argv)
    end
    rpm_names = rpm_names.join(',')
    real_argvs.push("rpm_name=#{rpm_names} group_id=#{group_id}")
    extras_real_argvs.push("rpm_name=#{rpm_names} group_id=#{group_id}")

    return real_argvs, extras_real_argvs, rpm_names
  end


  # Example items in @createrepodata_complete_mq.queue "createrepodata_complete":
  #    { "upload_rpms" => ["/srv/rpm/upload/**/Packages/*.rpm", "/srv/rpm/upload/**/source/*.rpm"], "job_id": "xxxx"}
  # submit install-rpm task to the upload_rpms
  def submit_install_rpm
    createrepodata_complete_queue = @createrepodata_complete_mq.queue('createrepodata_complete')
    Thread.new do
      q = createrepodata_complete_queue.subscribe({ manual_ack: true }) do |info, _pro, msg|
        begin
          rpm_info = JSON.parse(msg)

          real_argvs, extras_real_argvs, rpm_names = parse_real_argvs(rpm_info)

          unless real_argvs.length == 3
            Process.fork do
              system(real_argvs.join(' '))
            end
          end
          Process.fork do
            system(extras_real_argvs.join(' '))
          end
          @createrepodata_complete_mq.ack(info)
        rescue StandardError => e
          @log.warn({
            "submit_install_rpm error message": e.backtrace
          }.to_json)
          @createrepodata_complete_mq.ack(info)
        end
      end
    end
  end
end

include Clockwork

do_local_pack
config_yaml('auto-submit')
hr = HandleRepo.new

hr.create_repo
hr.ack_create_repo_done
hr.handle_new_rpm
hr.submit_install_rpm

Thread.new do
  handler do |job|
    begin
      group_id = Time.new.strftime('%Y-%m-%d') + '-auto-install-rpm'
      puts "Running #{job}"
      hr.deal_pub_dir(group_id)
    rescue StandardError => e
      JSONLogger.new.warn({
        "deal_pub_dir error message": e.message
      }.to_json)
    end
  end

  every(1.day, 'update pub dir', at: '23:59')
end
