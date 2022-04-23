require 'jwt'

CCI_SRC ||= ENV['CCI_SRC'] || '/c/compass-ci'

require "#{CCI_SRC}/lib/constants.rb"

helpers do
  def generate_token(my_account, gitee_id)
    exp = Time.now.to_i + 4 * 3600
    payload = { my_account: my_account, gitee_id: gitee_id, exp: exp }
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
end