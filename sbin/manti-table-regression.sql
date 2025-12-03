CREATE TABLE regression(
        id		bigint,

        record_type 	string,
        errid           string,
        first_seen	bigint,
        last_seen	bigint,
        submit_time     bigint,

        metric_name 	string,
        direction       string,

        status          string,
        related_job 	string,
        related_commit 	string,

        j               json
)  engine='columnar' charset_table='U+0021..U+007E';
