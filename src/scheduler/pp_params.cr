# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Job
  private def set_pp_params
    temp_hash = Hash(String, JSON::Any).new

    if @hash["pp"]
      flat_hash(@hash["pp"].as_h, temp_hash)
    end

    self["pp_params"] = sort_keys_return_values(temp_hash)
  end

  private def flat_hash(old_hash, new_hash)
    old_hash.each do |key1, value1|
      if value1.as_h?
        next if value1.as_h.empty?

        temp_hash = Hash(String, JSON::Any).new
        value1.as_h.each do |key2, value2|
          temp_hash.merge!({"#{key1}-#{key2}" => value2})
        end

        flat_hash(temp_hash, new_hash)
      else
        new_hash.merge!({key1 => value1})
      end
    end
  end

  private def sort_keys_return_values(hash)
    values = [] of String
    items_size = 0

    hash.keys.sort.each do |key|
      value = format_string(hash[key].to_s)
      next if 0 == value.size

      if 40 > value.size + items_size + values.size
        values << value
        items_size += value.size
      else
        break
      end
    end

    return values.join("-")
  end

  private def format_string(original_str)
    temp = [] of String
    original_str.each_char do |char|
      if "#{char}" =~ /-|\w/
        temp << "#{char}"
      end
    end

    return temp.join()
  end
end