CREATE TABLE accounts(
	id			bigint,
	gitee_id                string,
	my_account              string,
	my_name                 string,
	my_email                string,
	my_token                string,
	my_login_name           string,
	my_commit_url           string,
	my_orgs                 string,
	my_tags                 string,
	my_roles                string,
	my_groups               string,
	my_projects             string,
	create_time             bigint,
	weight                  bigint,
	my_third_party_accounts	json
) charset_table='U+0021..U+007E';
