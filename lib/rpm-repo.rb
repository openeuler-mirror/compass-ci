#!/usr/bin/ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'fileutils'
require 'json'
require './mq_client'

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
  def initialize
    @mq = MQClient.new(MQ_HOST, MQ_PORT)
    @update = []
  end

  def handle_new_rpm
    queue = @mq.queue("update_repo")
    queue.subscribe({:block => true, :manual_ack => true}) do |info,  _pro, msg|
      rpm_info = JSON.parse(msg)
      rpm_info["upload_rpms"].each do |rpm|
        rpm_path = File.dirname(rpm).sub("upload", "testing")
        FileUtils.mkdir_p(rpm_path) unless File.directory?(rpm_path)

        dest = File.join(rpm_path.to_s, File.basename(rpm))
        @update << dest
        FileUtils.mv(rpm, dest)
        system("createrepo --update $(dirname #{rpm_path})")
      end
      update_pub_dir
      @mq.ack(info)
    end
  end

  def update_pub_dir
    @update.each do |rpm|
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
end

hr = HandleRepo.new
hr.handle_new_rpm
