#!/usr/bin/ruby

# This script forwards mail from SPOT and SailMail devices from one
# address to another (usually a distribution list) while stripping
# certain information from the mails.

require 'net/imap'
require 'net/smtp'

# configuration
MAIL_SERVER = 'mail.mvxcvi.com'
MAIL_DOMAIN = 'mvxcvi.com'
MAIL_ACCOUNT = 'kallisti@mvxcvi.com'
MAIL_PASSWORD = 'pr3tt13st'

SPOT_ADDRESS = 'noreply@findmespot.com'
SAILMAIL_ADDRESS = 'wde9906@sailmail.com'

FROM_ADDRESS = 'kallisti@mvxcvi.com'
FORWARD_ADDRESS = 'kallisti-followers@googlegroups.com'


# mail queue to send
$queue = Array.new


# open IMAP connection to check mail
imap = Net::IMAP.new(MAIL_SERVER)
imap.login(MAIL_ACCOUNT, MAIL_PASSWORD)
imap.select('INBOX')

# get new messages from SPOT
imap.search(['NOT', 'SEEN', 'FROM', SPOT_ADDRESS]).each { |id|
	
	mail = imap.fetch(id, ['ENVELOPE', 'BODY[TEXT]'])[0]
	
	subject = mail.attr['ENVELOPE'].subject
	body = mail.attr['BODY[TEXT]']
	
	body = body.split("\r\n\r\n \r\n\r\n")[0]
	
	message  = "From: #{FROM_ADDRESS}\r\n"
	message += "To: #{FORWARD_ADDRESS}\r\n"
	message += "Subject: SPOT Update\r\n"
	message += body.lstrip
	
	$queue << message
	
}

# get new messages from SailMail
imap.search(['NOT', 'SEEN', 'FROM', SAILMAIL_ADDRESS]).each { |id|
	
	mail = imap.fetch(id, ['ENVELOPE', 'BODY[TEXT]'])[0]
	
	subject = mail.attr['ENVELOPE'].subject
	body = mail.attr['BODY[TEXT]']
	
	# trim signature from mail and obscure address
	body = body.split('-------------------------------------------------')[0]
	body.gsub!(Regexp.new(SAILMAIL_ADDRESS, Regexp::IGNORECASE), '--- ADDRESS REDACTED ---')
	
	message  = "From: #{FROM_ADDRESS}\r\n"
	message += "To: #{FORWARD_ADDRESS}\r\n"
	message += "Subject: #{subject}\r\n"
	message += body
	
	$queue << message
	
}

# close IMAP connection
imap.logout
imap.disconnect


# open smtp connection to send mail
Net::SMTP.start(MAIL_SERVER, 25, MAIL_DOMAIN, MAIL_ACCOUNT, MAIL_PASSWORD, :plain) { |smtp|
	
	$queue.each { |message|
		smtp.send_message(message, FROM_ADDRESS, FORWARD_ADDRESS)
	}
	
}

