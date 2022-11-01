#!/usr/bin/ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'set'
require_relative '../lib/mq_client'
require_relative '../lib/json_logger.rb'
require_relative '../lib/config_account'
require_relative "#{ENV['LKP_SRC']}/lib/do_local_pack"
require_relative '../lib/constants.rb'

MQ_HOST = ENV['MQ_HOST'] || ENV['LKP_SERVER'] || '172.17.0.1'
MQ_PORT = ENV['MQ_PORT'] || 5672
PREFETCH_COUNT = 1

# ---------------------------------------------------------------------------------------------------------------------------------------
#
# SrcOepkgs used to handle the mq queue "src_oepkgs_webhook_info"
#
# Example items in @mq.queue "src_oepkgs_webhook_info":
# '{ "commit_id": "434ae6db72382374e252364d930dc6936fa1e4eb", "url": "https://gitee.com/src-oepkgs/kibana", "branch": "master" }'
#
# handle_src_oepkgs_web_hook
#   check_webhook_info:   check the necessary parameters
#   submit_rpmbuild_job:
#    from:
#       items: {"commit_id": "xxx", "url": "https://gitee.com/src-oepkgs/xxx"} in @mq.queue
#    get:
#       upstream_repo/upstream_commit
#    from:
#       branch: "openEuler-22.03-LTS"
#    get:
#       os_version
#
#    submit rpmbuild.yaml upstream_repo=xxx upstream_commit=yyy os_version=zzz
# @mq.ack(info)
class SrcOepkgs
  def initialize
    @pr_mq = MQClient.new(hostname: MQ_HOST, port: MQ_PORT, prefetch_count: PREFETCH_COUNT)
    @push_mq = MQClient.new(hostname: MQ_HOST, port: MQ_PORT, prefetch_count: PREFETCH_COUNT)
    @log = JSONLogger.new
  end

  def handle_src_oepkgs_pr_hook
    pr_queue = @pr_mq.queue('src_oepkgs_pr_hook')
    Thread.new do
      pr_queue.subscribe({ block: true, manual_ack: true }) do |info, _pro, msg|
        loop do
          begin
            src_oepkgs_pr_hook_info = JSON.parse(msg)
            check_pr_hook_info(src_oepkgs_pr_hook_info)
            submit_pr_rpmbuild_job(src_oepkgs_pr_hook_info)

            @pr_mq.ack(info)
            break
          rescue StandardError => e
            @log.warn({
              "handle_src_oepkgs_pr_hook error message": e.message
            }.to_json)
            @pr_mq.ack(info)
            break
          end
        end
      end
    end
  end

  def handle_src_oepkgs_web_hook
    push_queue = @push_mq.queue('src_oepkgs_web_hook')
    push_queue.subscribe({ block: true, manual_ack: true }) do |info, _pro, msg|
      loop do
        begin
          src_oepkgs_webhook_info = JSON.parse(msg)
          check_webhook_info(src_oepkgs_webhook_info)
          submit_rpmbuild_job(src_oepkgs_webhook_info)

          @push_mq.ack(info)
          break
        rescue StandardError => e
          @log.warn({
            "handle_src_oepkgs_web_hook error message": e.message
          }.to_json)
          @push_mq.ack(info)
          break
        end
      end
    end
  end

  def check_pr_hook_info(data)
    raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'no commit_id params' }) unless data.key?('new_refs')
    raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'no upstream repo url params' }) unless data.key?('url')
    raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'no upstream branch params' }) unless data.key?('submit_command')
  end

  def check_webhook_info(data)
    raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'no commit_id params' }) unless data.key?('commit_id')
    raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'no upstream repo url params' }) unless data.key?('url')
    raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'no upstream branch params' }) unless data.key?('branch')
  end

  def parse_os_version(upstream_branch)
    if upstream_branch == "master"
      os_version = "20.03-LTS-SP1"
    elsif upstream_branch.start_with?("openEuler-")
      os_version = upstream_branch.delete_prefix!("openEuler-")
    else
      os_version = nil
    end
    return os_version
  end

  def check_sig_yaml(project_name)
    oepkgs_management_path = "/srv/git/openeuler/o/oepkgs-management/oepkgs-management.git/"
    filelist = `git -C "#{oepkgs_management_path}" ls-tree --name-only -r HEAD:`.chomp
    sig_name = nil
    filelist.split().each do |filename|
      next unless filename.end_with?(".yaml")
      sig_name = filename.split('/')[1] if filename.end_with?("#{project_name}.yaml")
      break if sig_name
    end
    return sig_name
  end

  def parse_push_arg(src_oepkgs_webhook_info)
    upstream_commit = src_oepkgs_webhook_info['commit_id']
    upstream_repo = src_oepkgs_webhook_info['url']
    upstream_branch = src_oepkgs_webhook_info['branch']
    submit_argv = ["#{ENV['LKP_SRC']}/sbin/submit", "-i", "/c/lkp-tests/jobs/secrets_info.yaml"]

    submit_argv.push("upstream_repo=#{upstream_repo}")
    submit_argv.push("upstream_commit=#{upstream_commit}")

    return submit_argv, upstream_repo, upstream_branch
  end

  def parse_pr_arg(src_oepkgs_pr_hook_info)
    pr_num = src_oepkgs_pr_hook_info['submit_command']['pr_merge_reference_name'].split('/')[2]
    upstream_repo = src_oepkgs_pr_hook_info['url']
    upstream_branch = src_oepkgs_pr_hook_info['branch']
    upstream_commit = src_oepkgs_pr_hook_info['new_refs']['heads']['master']
    submit_argv = ["#{ENV['LKP_SRC']}/sbin/submit", "-i", "/c/lkp-tests/jobs/secrets_info.yaml"]

    src_oepkgs_pr_hook_info['submit_command'].each do |k, v|
      submit_argv.push("#{k}=#{v}")
    end
    submit_argv.push("pr_num=#{pr_num}")
    submit_argv.push("upstream_repo=#{upstream_repo}")
    submit_argv.push("upstream_commit=#{upstream_commit}")

    return submit_argv, upstream_branch
  end

  def submit_pr_rpmbuild_job(src_oepkgs_pr_hook_info)
    submit_argv, upstream_branch = parse_pr_arg(src_oepkgs_pr_hook_info)
    real_argvs = Array.new(submit_argv)

    os_version = parse_os_version(upstream_branch)
    raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'no os_version' }) unless os_version

    real_argvs.push("rpmbuild.yaml os=openeuler os_version=#{os_version} docker_image=openeuler:#{os_version}")
    real_argvs.push("mount_repo_name=oepkgs")
    real_argvs.push("mount_repo_addr=https://repo.oepkgs.net/openEuler/rpm/openEuler-#{os_version}/extras/\\\\\\$basearch")

    Process.fork do
      system(real_argvs.join(' '))
    end
  end

  def submit_rpmbuild_job(src_oepkgs_webhook_info)
    submit_argv, upstream_repo, upstream_branch = parse_push_arg(src_oepkgs_webhook_info)

    real_argvs = Array.new(submit_argv)

    project_name = upstream_repo.split('/')[-1].gsub('.git', '')
    sig_name = check_sig_yaml(project_name)
    raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'no sig_name' }) unless sig_name

    os_version = parse_os_version(upstream_branch)
    raise JSON.dump({ 'errcode' => '200', 'errmsg' => 'no os_version' }) unless os_version

    real_argvs.push("custom_repo_name=contrib/#{sig_name}")
    real_argvs.push("rpmbuild.yaml os=openeuler os_version=#{os_version} docker_image=openeuler:#{os_version}")
    real_argvs.push("mount_repo_name=oepkgs")
    real_argvs.push("mount_repo_addr=https://repo.oepkgs.net/openEuler/rpm/openEuler-#{os_version}/extras/\\\\\\$basearch")

    Process.fork do
      system(real_argvs.join(' '))
    end
  end
end

do_local_pack
so = SrcOepkgs.new

config_yaml('auto-submit')
so.handle_src_oepkgs_pr_hook
so.handle_src_oepkgs_web_hook
