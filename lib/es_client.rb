# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'elasticsearch'
require_relative 'es_query.rb'

# -------------------------------------------------------------------------------------------
# put_source_by_id(source_id, source_content)
#  - put a source to ES /<target>/_doc/<_id>, ingore the existence of source
#
# -------------------------------------------------------------------------------------------
class ESClient < ESQuery
  # put a source to ES ingore the existence of source
  # @source_content : Hash
  #   eg:{
  #        "id" => "xxxxxx",
  #        "email" => "xxx@xxx.com",
  #        ...
  #      }
  def put_source_by_id(source_id, source_content)
    @client.index(
      {
        index: @index, type: '_doc',
        id: source_id,
        body: source_content
      }
    )
  end
end
