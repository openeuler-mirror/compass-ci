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
# Example items in @mq.queue "update_repo": { "upload_rpms" => ["/srv/rpm/upload/**/Packages/*.rpm", "/srv/rpm/upload/**/source/*.rpm"]}
# handle_new_rpm
#    move /srv/rpm/upload/**/*.rpm to /srv/rpm/testing/**/*.rpm
#    update /srv/rpm/testing/**/repodate
# update_pub_dir
#    copy /srv/rpm/testing/**/*.rpm to /srv/rpm/pub/**/*.rpm
#    change /srv/rpm/pub/**/repodate
# @mq.ack(info)
class HandleRepo
  @@upload_dir_prefix = '/srv/rpm/upload/'
  def initialize
    @es = ESQuery.new(ES_HOSTS)
    @mq = MQClient.new(hostname: MQ_HOST, port: MQ_PORT)
    @log = JSONLogger.new
  end

  @@upload_flag = true
  @@create_repo_path = Set.new
  def handle_new_rpm
    queue = @mq.queue('update_repo')
    createrepodata_queue = @mq.queue('createrepodata')
    queue.subscribe({ block: true, manual_ack: true }) do |info, _pro, msg|
      loop do
        next unless @@upload_flag

        begin
          rpm_info = JSON.parse(msg)
          check_upload_rpms(rpm_info)
          createrepodata_queue.publish(msg)

          rpm_info['upload_rpms'].each do |rpm|
            rpm_path = File.dirname(rpm).sub('upload', 'testing')
            FileUtils.mkdir_p(rpm_path) unless File.directory?(rpm_path)
            @@create_repo_path << rpm_path

            dest = File.join(rpm_path.to_s, File.basename(rpm))
            FileUtils.mv(rpm, dest)
          end

          @mq.ack(info)
          break
        rescue StandardError => e
          @log.warn({
            "handle_new_rpm error message": e.message
          }.to_json)
          @mq.ack(info)
          break
        end
      end
    end
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

  def deal_pub_dir(group_id)
    result_list = get_results_by_group_id(group_id)
    update = []
    result_list.each do |pkg_info|
      query = {
        'query' => {
          'query_string' => {
            'query' => "softwareName:#{pkg_info['softwareName']}"
          }
        }
      }.to_json

      next unless pkg_info['install'] == 'pass'
      next unless pkg_info['downloadLink']
      next unless pkg_info['src_location']

      job_id = pkg_info['result_root'].split('/')[-1]
      pkg_info.merge!(get_srpm_addr(job_id))
      update_compat_software?('srpm-info', query, pkg_info)

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
      raise JSON.dump({ 'errcode' => '200', 'errmsg' => "#{rpm} not exist" }) unless File.exist?(rpm)
      raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'the upload directory is incorrect' }) unless File.dirname(rpm).start_with?(@@upload_dir_prefix)
    end
  end

  def update_pub_dir(update)
    pub_path_list = Set.new
    update.each do |rpm|
      pub_path = File.dirname(rpm).sub('testing', 'pub')
      FileUtils.mkdir_p(pub_path) unless File.directory?(pub_path)

      dest = File.join(pub_path, File.basename(rpm))
      FileUtils.cp(rpm, dest)
      pub_path_list << pub_path
    end

    pub_path_list.each do |pub_path|
      system("createrepo --update $(dirname #{pub_path})")
    end
  end

  def create_repo
    createrepodata_queue = @mq.queue('createrepodata')
    createrepodata_complete_queue = @mq.queue('createrepodata_complete')
    Thread.new do
      loop do
        sleep 20
        next if @@create_repo_path.empty?

        @@upload_flag = false
        # Avoid mv in handle_new_rpm() is not over.
        sleep 1
        @@create_repo_path.each do |path|
          system("createrepo --update $(dirname #{path})")
        end

        q = createrepodata_queue.subscribe({ manual_ack: true }) do |info, _pro, msg|
          begin
            createrepodata_complete_queue.publish(msg)
            @mq.ack(info)
          rescue StandardError => e
            @log.warn({
              "create_repo error message": e.message
            }.to_json)
            @mq.ack(info)
          end
        end

        sleep 1
        q.cancel
        @@create_repo_path.clear
        @@upload_flag = true
      end
    end
  end

  def parse_arg(rpm_path, job_id)
    query_result = @es.query_by_id(job_id)
    submit_argv = ["#{ENV['LKP_SRC']}/sbin/submit"]
    rpm_path = File.dirname(rpm_path).sub('upload', 'testing')
    rpm_path.sub!('/srv', '')
    mount_repo_name = rpm_path.split('/')[4..-3].join('/')
    rpm_path = "https://api.compass-ci.openeuler.org:20018#{rpm_path}"
    rpm_path = rpm_path.delete_suffix('/Packages')
    submit_arch = rpm_path.split('/')[-1]
    submit_argv.push("mount_repo_addr=#{rpm_path}")
    submit_argv.push("arch=#{submit_arch}")
    submit_argv.push("mount_repo_name=#{mount_repo_name}")
    submit_argv.push("os=#{query_result['os']}")
    submit_argv.push("os_version=#{query_result['os_version']}")
    submit_argv.push("tbox_group=#{query_result['tbox_group']}")
    submit_argv.push("rpmbuild_job_id=#{job_id}")
    submit_argv.push("docker_image=#{query_result['docker_image']}") if query_result.key?('docker_image')

    fixed_arg = YAML.load_file('/etc/submit_arg.yaml')
    submit_argv.push((fixed_arg['yaml']).to_s)

    return submit_argv, submit_arch
  end

  def submit_install_rpm
    queue = @mq.queue('createrepodata_complete')
    queue.subscribe({ manual_ack: true }) do |info, _pro, msg|
      begin
        group_id = Time.new.strftime('%Y-%m-%d') + '-auto-install-rpm'
        rpm_info = JSON.parse(msg)
        job_id = rpm_info['job_id']

        rpm_names = []
        real_argvs = []
        rpm_info['upload_rpms'].each do |rpm|
          submit_argv, submit_arch = parse_arg(rpm, job_id)
          next if submit_arch == 'source'

          # zziplib-0.13.62-12.aarch64.rpm => zziplib-0.13.62-12.aarch64
          # zziplib-help.rpm
          # zziplib-doc.rpm
          rpm_name = File.basename(rpm).delete_suffix('.rpm')
          rpm_names << rpm_name
          real_argvs = Array.new(submit_argv)
        end
        rpm_names = rpm_names.join(',')
        real_argvs.push("rpm_name=#{rpm_names}")
        real_argvs.push("group_id=#{group_id}")
        system(real_argvs.join(' '))
        @mq.ack(info)
      rescue StandardError => e
        @log.warn({
          "submit_install_rpm error message": e.message
        }.to_json)
        @mq.ack(info)
      end
    end
  end
end

include Clockwork

do_local_pack
hr = HandleRepo.new

Thread.new do
  config_yaml('auto-submit')
  hr.create_repo
  hr.submit_install_rpm
  hr.handle_new_rpm
end

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
