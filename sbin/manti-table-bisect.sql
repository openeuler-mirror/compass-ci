CREATE TABLE bisect(
    id                      bigint,
    bad_job_id              string,
    error_id                string,
    bisect_status           string,
    bisect_metrics          string,
    project                 string,
    git_url                 string,
    bad_commit              string,
    first_bad_id            string,
    first_result_root       string,
    work_dir                string,
    start_time              BIGINT,
    end_time                BIGINT,
    priority_level          INT,
    timeout                 INT
) charset_table='U+0021..U+007E';
