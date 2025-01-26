
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
	submit_id	bigint indexed,
	submit_time	bigint indexed,
	boot_time	bigint indexed,
	finish_time	bigint indexed,
	boot_seconds	int indexed,
	run_seconds	int indexed,

	j		json,
	full_text_kv	text indexed,

) engine='columnar' charset_table='U+0021..U+007E';

desc jobs;
