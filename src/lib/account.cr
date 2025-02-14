
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
