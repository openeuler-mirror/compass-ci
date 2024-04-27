
# https://manual.manticoresearch.com/Updating_table_schema_and_settings

CREATE TABLE jobs(
	id		bigint,
	submit_id	bigint,
	submit_time	bigint,
	submit_date	string,

	my_account	string,
	my_name		string,

	suite		string,
	category	string,

	os		string,
	os_version	string,
	os_arch		string,

	osv		string,
	os_mount	string,
	rootfs		string,

	queue		string,
	subqueue	string,

	lab		string,
	tbox_group	string,
	testbox		string engine='rowwise',

	job_stage	string engine='rowwise',
	job_health	string engine='rowwise',

	boot_time	bigint engine='rowwise',
	finish_time	bigint engine='rowwise',
	active_time	bigint engine='rowwise',

	boot_seconds	int engine='rowwise',
	run_seconds	int engine='rowwise',

	jj		json engine='rowwise',
	mutable_vars	string stored engine='rowwise',
	other_data	string stored,
	full_text_words text indexed,
) engine='columnar';

desc jobs;
