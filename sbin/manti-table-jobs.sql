CREATE TABLE jobs(
	id		bigint,

	suite		string,
	category	string,
	my_account	string,
	testbox		string,
	arch		string,
	osv		string,

	submit_time	bigint,
	boot_time	bigint,
	running_time	bigint,
	finish_time	bigint,

	boot_seconds	int,
	run_seconds	int,

	istage		int,
	ihealth		int,

	j		json,
	errid		text,
	full_text_kv	text

) engine='columnar' charset_table='U+0021..U+007E'
