# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require_relative 'es_query.rb'

# -------------------------------------------------------------------------------------------
# put_source_by_id(source_id, source_content)
#  - put a source to ES /<target>/_doc/<_id>, ingore the existence of source
#
# opendistro_sql(search_sql)
#  - search es db by search_sql, search_sql is sql, like "SELECT * FROM JOBS WHERE ..."
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

  # search es db by search_sql, search_sql is sql, like:
  #   - "SELECT id, suite FROM JOBS"
  #   - "SELECT * FROM accounts WHERE my_account='test_user'"
  # this plugin from: https://github.com/NLPchina/elasticsearch-sql
  # this will be update to api: _opendistro/_sql
  def opendistro_sql(search_sql)
    @client.perform_request('POST', '_nlpcn/sql', {}, search_sql)
  end
end
