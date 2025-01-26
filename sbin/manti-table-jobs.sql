
# https://manticoresearch.com/blog/basics-of-manticore-indexes/
# https://manual.manticoresearch.com/Updating_table_schema_and_settings
# /c/manticoresearch/manual/Creating_a_table/NLP_and_tokenization/Low-level_tokenization.md
# https://www.ime.usp.br/~pf/algorithms/appendices/ascii.html

# Actions during the job lifecycle:
# - initial INSERT: submit initial job spec
# - stage REPLACE: when job is consumed and run
# - final REPLACE: add lots of errid/stats/result
# - data SEARCH: batch queries from cli/web ui, compare, bisect, etc.

# the 'rowwise' fields are in order of mutable, in hope of improving efficiency: int/json/string 

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
	full_text_kv	text indexed

) engine='columnar' charset_table='U+0021..U+007E'
