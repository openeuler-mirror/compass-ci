
class AccountInfo

  include JSON::Serializable
  # keey in synce with sbin/manti-table-accounts.sql
  property id                 :    Int64 = 0
  property gitee_id           :    String
  property my_account         :    String
  property my_commit_url      :    String
  property my_email           :    String
  property my_login_name      :    String
  property my_name            :    String
  property my_token           :    String
  property weight             :    Int32
  property my_third_party_accounts : Hash(String, String)

  def set_id
    if @id == 0
      @id = Manticore.hash_string_to_i64(@my_account)
    end
  end

  def id64
    @id
  end

  def id_es
    @id
  end

  def to_json_any
    JSON.parse(self.to_json)
  end

  def to_manticore
    JSON.parse(self.to_json)
  end

end

class Accounts
  property accounts : Hash(String, AccountInfo)
  @es : Elasticsearch::Client

  def initialize(es)
    @es = es
    @accounts = Hash(String, AccountInfo).new
  end

  def get_account(my_account : String) : AccountInfo | Nil
    return @accounts[my_account] if @accounts.has_key? my_account
    find_account_in_es({"my_account" => my_account})
    @accounts[my_account]?
  end

  def add_account(account_info : AccountInfo)
      @accounts[account_info.my_account] = account_info
  end

  private def find_account_in_es(matches : Hash(String, String)) : AccountInfo | Nil
    results = @es.select("accounts", matches)
    results.each do |hit|
      account = AccountInfo.from_json(hit["_source"].to_json)
      add_account(account)
    end
  end

  # Verify account authentication
  def verify_account(request : Hash(String, JSON::Any)) : Result
    error_msg = <<-MSG
      Failed to verify the account.
      Please refer to https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/apply-account.md
    MSG

    # Check for required key "my_account"
    unless request.has_key?("my_account")
      missing_key_error = <<-MSG
        Missing required job key: my_account
        If you applied for an account, please add my_account/my_token/my_email/my_name info to:
        ~/.config/compass-ci/defaults/account.yaml
      MSG
      return Result.error(HTTP::Status::BAD_REQUEST, missing_key_error)
    end

    # Validate account information
    ok = is_valid_account?(request)
    if ok
      Result.success("Account verified successfully")
    elsif ok == false
      Result.error(HTTP::Status::UNAUTHORIZED, error_msg)
    else
      Result.error(HTTP::Status::NOT_FOUND, "Account #{request["my_account"].as_s} not found")
    end
  end

  # Validate account information
  private def is_valid_account?(request : Hash(String, JSON::Any)) : Bool?
    return true if Sched.options.skip_account_verification

    account_info = get_account(request["my_account"].as_s)
    unless account_info
      return nil
    end

    request["my_token"].as_s == account_info.my_token
  end

end

# Always create/update account info via this API, so we are informed to change
# in-memory cache. For safety, only allow api_register_account() from internal
# IP and admin account.
class Sched
  def check_address(addr)
    if addr.is_a?(Socket::IPAddress)
      ip = addr.address
      return true if ip && Utils.private_ip?(ip)
    else
      return false
    end
  end

  def detect_local_client(env)
    return false unless check_address(env.request.local_address)
    return false unless check_address(env.request.remote_address)
    return true
  end

  def api_register_account(account_name : String, account_hash : Hash(String, JSON::Any)) : Result
    begin
      # Parse and validate account information
      account_info = AccountInfo.from_json(account_hash.to_json)

      # Add the account to the cache and Elasticsearch
      @accounts_cache.add_account(account_info)
      @es.replace_doc("accounts", account_info)

      # Return success result
      Result.success("Account registered successfully: #{account_name}")
    rescue ex
      # Log the error for debugging
      @log.error(exception: ex) { "Failed to register account: #{account_name}" }

      # Return error result
      Result.error(HTTP::Status::INTERNAL_SERVER_ERROR, ex.message || "Internal server error")
    end
  end

end
