#!/usr/bin/env ruby
# frozen_string_literal: true

require "#{ENV['CCI_SRC']}/lib/git_mirror"

git_mirror = MirrorMain.new

git_mirror.create_workers
git_mirror.main_loop
