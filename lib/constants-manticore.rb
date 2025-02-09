# included from both ruby and crystal

# these are suitable as direct fields
# - read frequently: common/useful in end user query
# - write once: won't change after initial submit
MANTI_STRING_FIELDS = %w[suite category my_account testbox arch osv]

# these can be in-place updated at low cost
MANTI_INT64_FIELDS = %w[id submit_time boot_time running_time finish_time]
MANTI_INT32_FIELDS = %w[boot_seconds run_seconds istage ihealth]

# their k=v will be added to full_text_kv for fast MATCH query
# MANTI_STRING_FIELDS will be added too
MANTI_FULLTEXT_FIELDS = %w[
    tbox_type build_type spec_file_name
    queue all_params_md5 pp_params_md5 tbox_group hostname
    host_machine group_id os os_version
    pr_merge_reference_name job_stage job_health
    last_success_stage os_project package build_id os_variant
]
MANTI_FULLTEXT_ARRAY_FIELDS = %w[
    target_machines
]

# for auto substitution in query input/output
MANTI_JSON_PROPERTIES = MANTI_FULLTEXT_FIELDS + MANTI_FULLTEXT_ARRAY_FIELDS
