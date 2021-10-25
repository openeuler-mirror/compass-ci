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
  @@upload_dir_prefix = "/srv/rpm/upload/"
  def initialize
    @mq = MQClient.new(MQ_HOST, MQ_PORT)
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

  def check_upload_rpms(data)
    raise JSON.dump({ "errcode" => "200", "errmsg" => "no upload_rpms params" }) unless data.key?("upload_rpms")
    raise JSON.dump({ "errcode" => "200", "errmsg" => "upload_rpms params type error" }) if data["upload_rpms"].class != Array
    data["upload_rpms"].each do |rpm|
      raise JSON.dump({ "errcode" => "200", "errmsg" => "#{rpm} not exist" }) unless File.exist?(rpm)
      raise JSON.dump({ "errcode" => "200", "errmsg" => "the upload directory is incorrect" }) unless File.dirname(rpm).start_with?(@@upload_dir_prefix)
    end
  end

  def update_pub_dir(update)
    update.each do |rpm|
      pub_path = File.dirname(rpm).sub("testing", "pub")
      FileUtils.mkdir_p(pub_path) unless File.directory?(pub_path)

      dest = File.join(pub_path, File.basename(rpm))
      FileUtils.cp(rpm, dest)

      repodata_dest = File.join(File.dirname(pub_path), "repodata")
      repodata_src = File.dirname(rpm).sub("Packages", "repodata")

      FileUtils.rm_r(repodata_dest) if Dir.exist?(repodata_dest)
      FileUtils.cp_r(repodata_src, File.dirname(repodata_dest))
    end
  end

  def create_repo
    createrepodata_queue = @mq.queue('createrepodata')
    createrepodata_complete_queue = @mq.queue('createrepodata_complete')
    Thread.new do
      loop do
        sleep 180
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

  def parse_arg(rpm_path)
    submit_argv = ["#{ENV['LKP_SRC']}/sbin/submit --no-pack"]
    rpm_path = File.dirname(rpm_path).sub('upload', 'testing')
    rpm_path.sub!('/srv', '')
    rpm_path = "https://api.compass-ci.openeuler.org:20018#{rpm_path}"
    rpm_path = rpm_path.delete_suffix('/Packages')
    submit_arch = rpm_path.split('/')[-1]
    submit_argv.push("custom_repo_addr=#{rpm_path}")
    submit_argv.push("arch=#{submit_arch}")
    submit_argv.push("custom_repo_name=#{rpm_path.split('/')[-2]}")

    fixed_arg = YAML.load_file("/etc/submit_arg.yaml")
    submit_argv.push("docker_image=#{fixed_arg['docker_image']}")
    submit_argv.push("testbox=#{fixed_arg['testbox']}")
    submit_argv.push("#{fixed_arg['yaml']}")

    return submit_argv, submit_arch
  end

  def submit_install_rpm
    queue = @mq.queue('createrepodata_complete')
    queue.subscribe({ manual_ack: true }) do |info, _pro, msg|
      begin
        group_id = Time.new.strftime('%Y-%m-%d')+'-auto-install-rpm'
        rpm_info = JSON.parse(msg)
        rpm_info['upload_rpms'].each do |rpm|
          submit_argv, submit_arch = parse_arg(rpm)
          real_argvs = Array.new(submit_argv)
          next if submit_arch == 'source'

          # zziplib-0.13.62-12.aarch64.rpm => zziplib
          rpm_name = $1 if File.basename(rpm) =~ %r{(.*)(-[^-]+){2}}
          real_argvs.push("rpm_name=#{rpm_name}")
          real_argvs.push("group_id=#{group_id}")
          system(real_argvs.join(' '))
        end
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

config_yaml('auto-submit')
do_local_pack()
hr = HandleRepo.new
hr.create_repo
hr.submit_install_rpm
hr.handle_new_rpm
