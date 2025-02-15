
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
  @accounts : Hash(String, AccountInfo)
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

  def verify_account(request : Hash(String, JSON::Any))
    error_msg = "Failed to verify the account.\n"
    error_msg += "Please refer to https://gitee.com/openeuler/compass-ci/blob/master/doc/user-guide/apply-account.md"

    unless request.has_key? "my_account"
      error_msg = "Missing required job key: my_account\n"
      error_msg += "If you applied account, please add my_account/my_token/my_email/my_name info to: "
      error_msg += "~/.config/compass-ci/defaults/account.yaml\n"
      raise error_msg
    end

    return if is_valid_account?(request)

    raise error_msg
  end

  private def is_valid_account?(request)
    account_info = get_account(request["my_account"].as_s)
    raise "no account for #{request["my_account"].as_s}" unless account_info

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

  def api_register_account(env)
    return unless detect_local_client(env)

    account_hash = JSON.parse(env.request.body.not_nil!.gets_to_end).as_h
    pass = account_hash.delete("admin_token")
    return unless pass
    return unless pass.as_s == Sched.options.admin_token

    account_info = AccountInfo.from_json(account_hash.to_json)
    @accounts_cache.add_account(account_info)
    @es.replace_doc("accounts", account_info)
  end
end
