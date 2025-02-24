CREATE TABLE accounts(
	id			bigint,
	gitee_id                string,
	my_account              string,
	my_commit_url           string,
	my_email                string,
	my_login_name           string,
	my_name                 string,
	my_token                string,
	weight                  int,
	my_third_party_accounts	json
) charset_table='U+0021..U+007E';
