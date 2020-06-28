# frozen_string_literal: true

require 'elasticsearch'

# build multiple query request body
class ESQuery
  def initialize(host, port)
    @client = Elasticsearch::Client.new url: "http://#{host}:#{port}"
    raise 'Connect Elasticsearch  error!' unless @client.ping
  end

  # Example @items: { key1 => value1, key2 => [value2, value3, ..], ...}
  # means to query: key1 == value1 && (key2 in [value2, value3, ..])
  def multi_field_query(items)
    query_fields = []
    items.each do |key, value|
      if value.is_a?(Array)
        inner_query = []
        value.each do |inner_value|
          inner_query.push({ term: { key => inner_value } })
        end
        query_fields.push({ bool: { should: inner_query } })
      else
        query_fields.push({ term: { key => value } })
      end
    end

    query = {
      query: {
        bool: {
          must: query_fields
        }
      }
    }
    @client.search index: 'jobs', body: query
  end
end
