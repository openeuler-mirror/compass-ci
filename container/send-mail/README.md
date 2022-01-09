# send mail

## purpose

The service is used to send mails with formatted mail data
- send intranet mail
- send internet mail

## send mail port
- send intranet mail: 11311
- send internet mail: 10001

## send mail host
- host the service running on

## data format
case you want to add an attachment file, please use send_mail_yaml,
then add attach_name and attach_content to the mail data as the following example:
- send_mail_yaml
	data='{
	"subject": "email subject",
	"to": "email_to_addr",
	"cc": "email_cc_addr",
	"bcc": "email_bcc_addr",
	"body": "email message",
	"attach_name": "attachment file name",
	"attach_content": "attachment file content"
	}'
    or
	data="
	subject: email subject
	to: email_to_addr
	cc: email_cc_addr
	bcc: email_bcc_addr
	body: email message
	attach_name: attachment file name
	attach_content: attachment file content
	"

- send_mail_text
	data="
	To: email_to_addr
	Cc: email_cc_addr
	Bcc: email_bcc_addr
	Subject: email_subject

	mail_msg_line1
	mail_msg_line2
	...
	"

sometimes the mail content may contain special char, and it will lead
to failure when access the api, encode the data before use it.
- send_mail_encode
	data="
	To: email_to_addr
	Cc: email_cc_addr
	Bcc: email_bcc_addr
	Subject: email_subject

	mail_msg_line1
	mail_msg_line2
	...
	"

	data=$(echo $data | base64)

## usage:
- send_mail_yaml
    ```shell
    curl -XPOST '#{SEND_MAIL_HOST}:#{SEND_MAIL_PORT}/send_mail_yaml' -d "$data"
    ```

- send_mail_text
    ```shell
    curl -XPOST '#{SEND_MAIL_HOST}:#{SEND_MAIL_PORT}/send_mail_text' -d "$data"
    ```

- send_mail_encode
    ```shell
    curl -XPOST '#{SEND_MAIL_HOST}:#{SEND_MAIL_PORT}/send_mail_encode' -d "$data"
    ```

## example

```ruby
    data = "
    To: test_email@163.com
    Subject: test mail 10

    test msg 1010
    "

    %x(curl -XPOST 'localhost:10001/send_mail_text' -d "#{data}")
```
