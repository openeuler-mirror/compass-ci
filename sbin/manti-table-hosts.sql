CREATE TABLE hosts(
	id			bigint,
	nr_node			int,
	nr_cpu			int,
	memory			int,
	nr_disks		int,
	nr_hdd_partitions	int,
	nr_ssd_partitions	int,

	create_time		bigint,
	boot_time		bigint,
	reboot_time		bigint,
	active_time		bigint,

	job_id			bigint,

	full_text_kv		text,
	j			json
) charset_table='U+0021..U+007E';
