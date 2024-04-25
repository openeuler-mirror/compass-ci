# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Job < JobHash
  private def sort_pp_params
    return unless hh = @hash_hhh["pp"]?

    return sort_keys_return_values(flat_hh(hh))
  end

  private def flat_hh(hh)
    temp_hash = Hash(String, String).new
    hh.each do |k, v|
      next unless v
      v.each do |kk, vv|
        next unless vv
        temp_hash["#{k}.#{kk}"] = vv
      end
    end
    temp_hash
  end

  private def sort_keys_return_values(hash)
    values = [] of String
    items_size = 0

    hash.keys.sort.each do |key|
      value = format_string(hash[key])
      next if 0 == value.size

      if items_size < 40
        value = value[0...(40-items_size)] if items_size + value.size > 40
        values << value
        items_size += value.size
      else
        break
      end
    end

    return values.join("-").strip.strip("-")
  end

  private def format_string(original_str)
    temp = [] of String
    original_str.gsub('/', '-').each_char do |char|
      temp << "#{char}" if "#{char}" =~ /\w|-|\./
    end

    return temp.join()
  end
end
