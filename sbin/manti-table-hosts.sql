CREATE TABLE hosts(
	id			bigint,
	nr_node			int,
	nr_cpu			int,
	memory			int,
	nr_disks		int,
	nr_hdd_partitions	int,
	nr_ssd_partitions	int,

	active_time		int,
	job_id			bigint,

	j			json,
	full_text_kv		text
) engine='columnar' charset_table='U+0021..U+007E'
