require 'jwt'

CCI_SRC ||= ENV['CCI_SRC'] || '/c/compass-ci'

require "#{CCI_SRC}/lib/constants.rb"
require "#{CCI_SRC}/lib/es_client"

JWT_SECRET ||= %x(uuidgen).chomp

helpers do
  def generate_token(my_account, openeuler_username, openeuler_email, roles)
    exp = Time.now.to_i + 4 * 3600
    payload = { my_account: my_account, openeuler_username: openeuler_username, openeuler_email: openeuler_email, roles: roles, exp: exp }
    token = JWT.encode(payload, JWT_SECRET, "HS256")
    return token
  end

  # helper to extract the token header
  def extract_token
    # check for header
    token = request.env["HTTP_AUTHORIZATION"]
    return token
  end

  # check the token to make sure it is valid
  def authorized?
    token = extract_token
    return nil if token.nil?

    begin
      payload, header = JWT.decode(token, JWT_SECRET, true, { algorithm: 'HS256'} )
      exp = payload["exp"]
      # check to see if the exp is set
      return nil if exp.nil?

      exp = Time.at(exp.to_i)
      # make sure the token hasn't expired
      return nil if Time.now > exp

    rescue JWT::DecodeError => e
      return nil
    end

    return payload
  end

  def check_account_info(payload)
    es = ESClient.new(index: 'accounts')
    body = es.multi_field_query({ 'my_third_party_accounts.openeuler_username' => payload['openeuler_username'] }, single_index: true)['hits']['hits'][0]
    return nil if body.nil?

    account_info = body['_source']
    return nil unless account_info['my_account'].eql?(payload['my_account']) && account_info['roles'].eql?(payload['roles'])
    payload.merge!({"account_info" => account_info})

    return payload
  end 

  def auth(params)
    payload = authorized?

    unless params.delete(:isVisitor)
      throw(:halt, [401, headers.merge('Access-Control-Allow-Origin' => '*'), 'token expires']) if payload.nil?
      throw(:halt, [403, headers.merge('Access-Control-Allow-Origin' => '*'), 'this openeuler community user does not have a compass account']) if payload['my_account'].nil?
    end

    payload = check_account_info(payload)

    return payload
  end
  
end
