# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

# helper for (task) block
class BlockHelper
  def initialize
    @block_helper = Hash(String, Fiber).new
  end

  # waiting untill special uuid's task is finished
  # - yield (block) returns false, all uuid's task will block
  # - yield returns true, then all uuid's task will continue
  #
  # examples:
  #  block_helper = BlockHelp.new  # global instance
  #
  #  # fiber-A call below code (checkfile: function / variable)
  #  #   when "checkfile == false", then fiber-A blocked
  #  # fiber-B call below code too
  #  #   when "checkfile == true", then fiber-A and B continues
  #  block_helper.block_until_finished("1") { checkfile }
  #
  def block_until_finished(uuid)
    if @block_helper[uuid]?
      fiber = @block_helper[uuid]
    else
      fiber = Fiber.new { puts "uuid {#{uuid}} finished" }
      @block_helper[uuid] = fiber
    end

    spawn fiber.run if yield == true

    until fiber.dead?
      Fiber.yield
    end

    @block_helper.delete(uuid)
  end
end
