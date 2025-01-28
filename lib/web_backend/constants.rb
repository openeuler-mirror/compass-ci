ONE_DAY_SECOND = 3600 * 24
ACCOUNT_MIN_LEN = 3
ACCOUNT_MAX_LEN = 20
AUTH_CODE_MIN_LEN = 6
AUTH_CODE_MAX_LEN = 32
EMAIL_MAX_LEN = 64
ITERATION = 150000
KEY_LENGTH = 32
SALT_LENGTH = 16
EMAIL_PATTERN = /^(([^<>\(\)\[\]\\\.,;:\s@"]+(\.[^<>\(\)\[\]\\\.,;:\s@"]+)*)|(".+"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/
AUTH_CODE_PATTERN = /^[a-zA-Z0-9!@#$%^&*?]*(?=\S{6,})(?=\S*\d)(?=\S*[A-Z])(?=\S*[a-z])(?=\S*[!@#$%^&*? ])[a-zA-Z0-9!@#$%^&*?]*$/