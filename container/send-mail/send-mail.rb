#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'mail'

mail_server = `/sbin/ip route |awk '/default/ {print $3}'`.chomp

# setup smtp config
smtp = {
  address: mail_server,
  enable_starttls_auto: false
}

Mail.defaults { delivery_method :smtp, smtp }

# send mail
def send_mail(mail_info)
  mail = Mail.new do
    references mail_info['references']
    from mail_info['from']
    subject mail_info['subject']
    to mail_info['to']
    body mail_info['body']
  end
  mail.deliver!
end
