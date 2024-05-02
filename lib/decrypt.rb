require 'json'

def decrypt_text(decrypt_info)
  decrypt_info = decrypt_info.to_json
  `python3 #{Dir.pwd}/decrypt.py '#{decrypt_info}'`
end

def decrypt_text_from_env
  return {} unless ENV['text_encrypt_ascii']

  decrypt_info = {
	  "encrypt_key" => ENV['encrypt_key'],
	  "work_key_encrypt" => ENV['work_key_encrypt'],
	  "work_key_encrypt_iv" => ENV['work_key_encrypt_iv'],
	  "text_iv_ascii" => ENV['text_iv_ascii'],
	  "text_encrypt_ascii" => ENV['text_encrypt_ascii']
  }
  text = decrypt_text(decrypt_info)
  return JSON.parse(text)
rescue StandardError => e
  puts e
  return {}
end
