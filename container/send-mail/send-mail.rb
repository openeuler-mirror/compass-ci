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
def send_mail(from, subject, to, body)
  mail = Mail.new do
    from from
    subject subject
    to to
    body body
  end
  mail.deliver!
end
