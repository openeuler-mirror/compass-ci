#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'mail'

ip_addr = `/sbin/ip route |awk '/default/ {print $3}'`.chomp

# setup smtp config
smtp = {
  address: ip_addr,
  enable_starttls_auto: false
}

Mail.defaults { delivery_method :smtp, smtp }

# send mail
def send_mail(subject, to, body)
  mail = Mail.new do
    subject subject
    from 'team@crystal.ci'
    to to
    body body
  end
  mail.deliver!
end
