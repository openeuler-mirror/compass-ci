# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require_relative 'es_query.rb'

# -------------------------------------------------------------------------------------------
# put_source_by_id(source_id, source_content)
#  - put a source to ES /<target>/_doc/<_id>, ingore the existence of source
# 
# query_by_sql(query_sql)
#  - query es db by query_sql, query_sql is sql, like "SELECT * FROM JOBS WHERE ..." 
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

  # query es db by query_sql, query_sql is sql, like:
  #   - "SELECT id, suite FROM JOBS"
  #   - "SELECT * FROM accounts WHERE my_account='test_user'"
  # this plugin from: https://github.com/NLPchina/elasticsearch-sql
  def query_by_sql(query_sql)
    @client.perform_request('GET', '_nlpcn/sql', {}, query_sql)
  end

end
