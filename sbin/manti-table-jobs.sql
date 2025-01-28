CREATE TABLE jobs(
	id		bigint,

	submit_time	bigint,
	boot_time	bigint,
	running_time	bigint,
	finish_time	bigint,

	boot_seconds	int,
	run_seconds	int,

	j		json,
	errid		text,
	full_text_kv	text

) engine='columnar' charset_table='U+0021..U+007E'
