# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

MAX_PAGE_SIZE = 30
MAX_SEARCH_NUM = 1000000

def check_es_size_num(page_size, page_num)
  if page_size > MAX_PAGE_SIZE
      raise "page_size to bigger than #{MAX_PAGE_SIZE}."
  end

  if page_num > MAX_SEARCH_NUM/page_size
    raise "page_num to bigger than #{MAX_SEARCH_NUM/page_size}."
  end
end
