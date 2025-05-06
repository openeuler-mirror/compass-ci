CREATE TABLE regression(
	id		bigint,

	record_type 	string,
        errid           string,
    	category        string,
    	first_seen	bigint,
    	last_seen	bigint,

    	metric_name 	string,
    	value 		float,

    	bisect_count 	bigint,
        valid           string,
    	related_jobs 	json
)  engine='columnar' charset_table='U+0021..U+007E';   

