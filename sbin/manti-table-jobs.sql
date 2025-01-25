
# curl -sX POST http://localhost:9308/cli -d "$(<manti-table-jobs.sql)"

# https://manticoresearch.com/blog/basics-of-manticore-indexes/
# https://manual.manticoresearch.com/Updating_table_schema_and_settings
# /c/manticoresearch/manual/Creating_a_table/NLP_and_tokenization/Low-level_tokenization.md
# https://www.ime.usp.br/~pf/algorithms/appendices/ascii.html

# Actions during the job lifecycle:
# - initial INSERT: submit initial job spec
# - stage UPDATE: when job is consumed and run, will update few 'rowwise' stage/time fields for many times
# - final REPLACE: add lots of errid/stats/result
# - data SEARCH: batch queries from cli/web ui, compare, bisect, etc.

# the 'rowwise' fields are in order of mutable, in hope of improving efficiency: int/json/string 

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

	pp_params_md5	string,
	all_params_md5	string,

	queue		string,

	lab		string,
	tbox_group	string,

	pp		json,
	ss		json,
	hw		json,

	boot_time	bigint engine='rowwise',
	running_time	bigint engine='rowwise',
	finish_time	bigint engine='rowwise',
	time		bigint engine='rowwise',

	boot_seconds	int engine='rowwise',
	run_seconds	int engine='rowwise',

	jj		json engine='rowwise',

	testbox		string engine='rowwise',

	job_stage	string engine='rowwise',
	job_health	string engine='rowwise',

	mutable_vars	string stored engine='rowwise',

	errid		string,
	stats		string stored,

	other_data	string stored,

	full_text_words text indexed,
) engine='columnar' charset_table='U+0021..U+007E';

desc jobs;
