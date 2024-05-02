import os
import sys
import json

sys.path.append(os.path.abspath("../"))
from lib.crypt_env import decrypt_text

try:
    decrypt_info_json = sys.argv[-1].replace("'", '"')
    decrypt_info = json.loads(decrypt_info_json)
    text = decrypt_text(
        decrypt_key=decrypt_info["encrypt_key"],
        work_key_encrypt=decrypt_info["work_key_encrypt"],
        work_key_encrypt_iv=decrypt_info["work_key_encrypt_iv"],
        text_iv_ascii=decrypt_info["text_iv_ascii"],
        text_encrypt_ascii=decrypt_info["text_encrypt_ascii"]
    )
    sys.stdout.write(text)
    sys.stdout.flush()
except Exception as e:
    print(e)
