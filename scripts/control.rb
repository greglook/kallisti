#!/usr/bin/ruby

# This script manages a local data store of waypoints.
#
# In order to operate, the script needs to know two things, the path to a
# YAML configuration file and the path to the YAML data file. These are
# provided by the --config and --file arguments, respectively.


require 'net/imap'
require 'optparse'
require 'time'
require 'yaml'

require 'kallisti/leg'
require 'kallisti/waypoint'
require 'kallisti/voyage'
require 'kallisti/kml'


##### GLOBALS #####

# this hash holds runtime options
$options = {
	:config_file => "config.yml",
	:data_file => "data.yml",
	:verbose => false,

	:full => false,
	:ignore_duplication => false,
	:merge_all => false,
}

# this hash holds persistent configuration
$config = { }

# possible actions the script can take
$actions = []

# IMAP connection object
$imap = nil

# the voyage object
$voyage = nil



##### UTILITY FUNCTIONS #####

# debug verbose print function
def verbose(msg, force = false)
	print(msg) if force or $options[:verbose]
end


# profiling function to simplify collecting runtimes
def profile(task_name, show = false)
	verbose("#{task_name}... ", show)
	STDOUT.flush
	start = Time.now
	begin
		value = yield
		elapsed = Time.now - start
		verbose("done. (%.3f seconds)\n" % elapsed, show)
		STDOUT.flush
		value
	rescue
		elapsed = Time.now - start
		verbose("caught exception! (%.3f seconds)\n" % elapsed, show)
		raise
	end
end



##### PERSISTENCE #####

# try to load configuration from a file
def load_config
	if File.exists? $options[:config_file]
		profile "Loading configuration from #{$options[:config_file]}" do
			config_file = nil
			File.open($options[:config_file]) {|file| config_file = YAML::load file }
			if config_file
				config_file.each {|key, value| $config[key] = value unless $config.has_key? key }
			else
				print " unable to load configuration from file!\n"
				exit 1
			end
		end
	else
		print "Configuration file #{$options[:config_file]} does not exist.\n"
	end
end


# save the current configuration to a file
def save_config
	profile "Saving configuration to " << $options[:config_file] do
		File.open($options[:config_file], 'w') {|file| file << $config.to_yaml }
	end
end


# load waypoint data from file
def load_data
	if File.exists? $options[:data_file]
		profile "Loading data from #{$options[:data_file]}" do
			File.open($options[:data_file]) {|file| $voyage = YAML::load file }
			unless $voyage.is_a? Kallisti::Voyage
				print " unable to load data from specified file!\n"
				exit 1
			end
		end
	else
		print "Data file #{$options[:data_file]} does not exist.\n"
	end
end


# updates/recalculates voyage route data
def reroute_data
	profile "Updating route data" do
		$voyage.update!
	end
end


# save waypoint data to file
def save_data
	profile "Saving data to #{$options[:data_file]}" do
		File.open($options[:data_file], 'w') {|file| file << $voyage.to_yaml }
	end
end



##### MAIL PROCESSING #####

# open IMAP connection to check mail
def open_imap
	raise "IMAP connection is already open!" if $imap
	raise "mail-server must be set!" unless $config[:mail_server]
	raise "mail-account must be set!" unless $config[:mail_account]
	raise "mail-password must be set!" unless $config[:mail_password]
	
	profile "Signing in to mail account #{$config[:mail_account]}" do
		$imap = Net::IMAP.new($config[:mail_server])
		$imap.login($config[:mail_account], $config[:mail_password])
		$imap.select('INBOX')
	end
end


# close IMAP connection
def close_imap
	raise "IMAP connection is already closed!" unless $imap
	
	$imap.logout
	$imap.disconnect
	$imap = nil
end


# fetch new SPOT messages
def update_spots
	raise "IMAP connection must be open!" unless $imap
	raise "spot-address must be set!" unless $config[:spot_address]
	
	# restrict fetches to after this date
	last_spot = $voyage.waypoints.reverse.find {|point| point.source == :spot }
	last_updated = (last_spot.nil? or $options[:merge_all]) ? Time.gm(1970, 1, 2) : last_spot.time
	last_updated = "%d-%s-%d" % [last_updated.day, Net::IMAP::DATE_MONTH[last_updated.month - 1], last_updated.year]
	
	# fetch mail ids
	mails = profile "Checking for new SPOT messages since #{last_updated}" do
		$imap.search(['SEEN', 'FROM', $config[:spot_address], 'SINCE', last_updated])
	end
	
	# return if no updates
	unless mails and not mails.empty?
		print "No new SPOTs found.\n"
		return
	end
	
	# fetch mail data
	mails = profile "Fetching #{mails.length} messages" do
		mails.collect {|id| $imap.fetch(id, ['ENVELOPE', 'BODY[TEXT]'])[0] }
	end
	
	deduped = []
	added = []
	
	# process spot mails
	profile "Processing messages" do mails.each do |mail|
		subject = mail.attr['ENVELOPE'].subject
		body = mail.attr['BODY[TEXT]']
		
		# parse out information
		time = Time.parse(body.scan(/Time:(.+?)\s*\r\n/)[0][0])
		latitude = body.scan(/Latitude:(\-?[0-9]+\.[0-9]+)/)[0][0].to_f
		longitude = body.scan(/Longitude:(\-?[0-9]+\.[0-9]+)/)[0][0].to_f
		message = body.match(/Message:Everything is OK/) ? 'OK' : 'SOS'
		
		raise "Could not parse time from SPOT message body: #{body}" unless time.is_a? Time
		raise "Could not parse latitude from SPOT message body: #{body}" unless latitude.is_a? Float
		raise "Could not parse longitude from SPOT message body: #{body}" unless longitude.is_a? Float
		
		point = Kallisti::Waypoint.new(:spot, time, Geocoordinate.new(latitude, longitude))
		if $voyage.add_point point
			added << point
		else
			deduped << point
		end
	end end
	
	unless deduped.empty?
		print "Deduplicated #{not_added.size} SPOTs:\n"
		deduped.each {|point| print point, "\n" }
	end
	
	unless added.empty?
		print "Added #{added.size} SPOTs to voyage:\n"
		added.each {|point| print point, "\n" }
	end
end


# fetch new SailMail messages
def update_sailmail
	raise "IMAP connection must be open!" unless $imap
	raise "sailmail-address must be set!" unless $config[:sailmail_address]
	
	# restrict fetches to after this date
	last_sailmail = $voyage.waypoints.reverse.find {|point| point.source == :sailmail }
	last_updated = (last_sailmail.nil? or $options[:merge_all]) ? Time.gm(1970, 1, 2) : last_sailmail.time
	last_updated = "%d-%s-%d" % [last_updated.day, Net::IMAP::DATE_MONTH[last_updated.month - 1], last_updated.year]
	
	# fetch mail ids
	mails = profile("Checking for new SailMail messages since " << last_updated) { $imap.search(['SEEN', 'FROM', $config[:sailmail_address], 'SINCE', last_updated]) }
	
	# return if no updates
	unless mails and not mails.empty?
		print "No new SailMail messages found.\n"
		return
	end
	
	# fetch mail data
	mails = profile "Fetching #{mails.length} messages" do
		mails.collect {|id| $imap.fetch(id, ['ENVELOPE', 'BODY[TEXT]'])[0] }
	end
	
	address_regex = Regexp.new($config[:sailmail_address], Regexp::IGNORECASE)
	
	deduped = []
	added = []
	
	# process spot mails
	profile("Processing messages") do mails.each do |mail|
		subject = mail.attr['ENVELOPE'].subject
		body = mail.attr['BODY[TEXT]']
		time = Time.parse(mail.attr['ENVELOPE'].date)
		
		# trim signature from mail and obscure address
		body = body.split('-------------------------------------------------')[0]
		body.gsub!(address_regex, '--- ADDRESS REDACTED ---')
		body.gsub!(/=\r\n/, '')
		
		raise "Could not parse time from SailMail message body: #{body}" unless time.is_a? Time
		
		point = Kallisti::Waypoint.new(:sailmail, time, nil, subject, body.chomp)
		if $voyage.add_point point
			added << point
		else
			deduped << point
		end
	end end
	
	unless deduped.empty?
		print "Deduplicated #{not_added.size} SailMails:\n"
		deduped.each {|point| print point, "\n" }
	end
	
	unless added.empty?
		print "Added #{added.size} SailMails to voyage:\n"
		added.each {|point| print point, "\n" }
	end
end



##### SCRIPT ACTIONS #####

$actions << {
	:name => 'config',
	:desc => "Prints out the current configuration",
	:proc => Proc.new do
		load_config
		$config.each {|k, v| print "#{k.to_s}: #{v}\n" }
	end
}

$actions << {
	:name => 'configure',
	:args => "<key> <value>",
	:desc => "Sets a configuration value in the config file",
	:proc => Proc.new do |key, value|
		raise "Must supply a key to set" unless key
		raise "Must supply a value" unless value
		
		load_config
		$config[key.intern] = value
		save_config
		print "Set configuration value for #{key.to_s}\n"
	end
}

$actions << {
	:name => 'new',
	:args => "<name> <desc> [author]",
	:desc => "Creates a new voyage record",
	:proc => Proc.new do |name, desc, author|
		raise "Must supply a voyage name" unless name
		raise "Must supply a voyage description" unless desc
		
		$voyage = Kallisti::Voyage.new(name, desc, author)
		save_data
		
		print "Created new voyage:\n#{$voyage}\n"
	end
}

$actions << {
	:name => 'show',
	:desc => "Prints a summary of the entire voyage",
	:proc => Proc.new do
		load_data
		print $voyage, "\n"
	end
}

$actions << {
	:name => 'show-legs',
	:args => "[from time] [to time]",
	:desc => "Prints the voyage legs between times 'from' and 'to'",
	:proc => Proc.new do |from, to|
		from = from ? Time.parse(from) : Time.at(0)
		to = to ? Time.parse(to) : Time.now
		
		load_data
		range = from..to
		$voyage.legs.each_with_index {|leg, i| print("%2d. %s\n" % [i+1, leg]) if ( range === leg.from ) or ( range === leg.to ) }
	end
}

$actions << {
	:name => 'show-points',
	:args => "[from time] [to time]",
	:desc => "Prints the voyage waypoints between times 'from' and 'to'",
	:proc => Proc.new do |from, to|
		from = from ? Time.parse(from) : Time.at(0)
		to = to ? Time.parse(to) : Time.now
		
		load_data
		range = from..to
		$voyage.waypoints.each_with_index {|point, i| print("%3d. %s\n" % [i+1, point]) if range === point.time }
	end
}

$actions << {
	:name => 'add-leg',
	:args => "<name> <start time> <end time>",
	:desc => "Adds a new leg to the voyage",
	:proc => Proc.new do |name, from, to|
		raise "Must supply a name" unless name
		raise "Must supply leg start time" unless from
		raise "Must supply leg end time" unless to
		
		from = Time.parse(from)
		to = Time.parse(to)
		leg = Kallisti::Leg.new(name, from, to)
		
		load_data
		if $voyage.add_leg leg
			reroute_data
			save_data
			print "Successfully added leg to voyage:\n#{leg}\n"
		else
			print "Failed to add leg to voyage:\n#{leg}\n"
		end
	end
}

$actions << {
	:name => 'add-waypoint',
	:args => "<time> <latitude> <longitude>",
	:desc => "Adds a new waypoint to the voyage",
	:proc => Proc.new do |time, latitude, longitude|
		raise "Must supply a time" unless time
		raise "Must supply waypoint latitude" unless latitude
		raise "Must supply waypoint longitude" unless longitude
		
		time = Time.parse(time)
		latitude = latitude.to_f
		longitude = longitude.to_f
		waypoint = Kallisti::Waypoint.new(:waypoint, time, Geocoordinate.new(latitude, longitude))
		
		load_data
		if $voyage.add_point waypoint, $options[:ignore_duplication]
			reroute_data
			save_data
			print "Successfully added waypoint to voyage:\n#{waypoint}\n"
		else
			print "Failed to add waypoint to the voyage, probably because of deduplication. To override this, use --ignore-duplication\n#{waypoint}\n"
		end
	end
}

$actions << {
	:name => 'add-message',
	:args => "<time> <title> <text>",
	:desc => "Adds a new message to the voyage",
	:proc => Proc.new do |time, title, text|
		raise "Must supply a time" unless time
		raise "Must supply message title" unless title
		raise "Must supply message text" unless text
		
		time = Time.parse(time)
		message = Kallisti::Waypoint.new(:message, time, nil, title, text)
		
		load_data
		if $voyage.add_point message, $options[:ignore_duplication]
			reroute_data
			save_data
			print "Successfully added message to voyage:\n#{message}\n"
		else
			print "Failed to add message to voyage, probably because of deduplication. To override this, use --ignore-duplication\n#{message}\n"
		end
	end
}

$actions << {
	:name => 'add-log',
	:args => "<time> <text>",
	:desc => "Adds a new ship's log entry to the voyage",
	:proc => Proc.new do |time, text|
		raise "Must supply a time" unless time
		raise "Must supply log text argument!" unless text
		
		time = Time.parse(time)
		title = "Ship's Log"
		log = Kallisti::Waypoint.new(:log, time, nil, title, text)
		
		load_data
		if $voyage.add_point log, $options[:ignore_duplication]
			reroute_data
			save_data
			print "Successfully added log entry to voyage:\n#{log}\n"
		else
			print "Failed to add log entry to voyage, probably because of deduplication. To override this, use --ignore-duplication\n#{log}\n"
		end
	end
}

$actions << {
	:name => 'update-spots',
	:desc => "Connects to the configured mail account to check for new SPOT messages",
	:proc => Proc.new do
		load_config
		load_data
		open_imap
		added = update_spots
		close_imap
		reroute_data
		save_data
	end
}

$actions << {
	:name => 'update-sailmail',
	:desc => "Connects to the configured mail account to check for SailMail messages",
	:proc => Proc.new do
		load_config
		load_data
		open_imap
		update_sailmail
		close_imap
		reroute_data
		save_data
	end
}

$actions << {
	:name => 'update',
	:desc => "Equivalent to the actions 'update-spots', 'update-sailmail', then 'show'",
	:proc => Proc.new do
		load_config
		load_data
		open_imap
		update_spots
		update_sailmail
		close_imap
		reroute_data
		save_data
		print "\n", $voyage, "\n"
	end
}

$actions << {
	:name => 'kml',
	:args => "[style]",
	:desc => "Prints a KML file in either 'map' or 'earth' style",
	:proc => Proc.new do |style|
		options = { }
		if style
			if style.downcase == 'earth'
				options[:time_info] = true
				options[:leg_folders] = true
			elsif style.downcase == 'map'
				options[:time_info] = false
				options[:leg_folders] = false
			end
		end
		
		load_data
		print $voyage.to_kml(options)
	end
}



##### COMMAND LINE INTERFACE #####

# set up command-line options
option_parser = OptionParser.new do |opts|
	opts.banner = "Usage: [options...] <action> [action parameters...]\n"
	
	opts.separator ""
	opts.separator "General Options"
	opts.on('-f', '--file FILE', "File containing waypoint dataset, or path to save new set") {|file| $options[:data_file] = file }
	opts.on('-c', '--config FILE', "Use the given file for configuration") {|file| $options[:config_file] = file }
	opts.on('-v', '--verbose', "Output detailed processing information") { $options[:verbose] = true }
	opts.on('-h', '--help', "Display this screen") { print opts; exit }
	
	opts.separator ""
	opts.separator "Action Options"
	opts.on('--full', "Show full texts instead of truncating") { $options[:full] = true }
	opts.on('--ignore-duplication', "Ignore duplication detection") { $options[:ignore_duplication] = true }
	opts.on('--merge-all', "Update with full mail history instead of from last-updated") { $options[:merge_all] = true }
	
	opts.separator ""
	opts.separator "Actions\n%s" % $actions.map{|act| "    %s %s\n        %s\n" % [act[:name], act[:args] || "", act[:desc]] }.join
end

# parse command line
option_parser.parse!

# get action from first argument
action_name = ( ARGV.length > 0 ) ? ARGV.shift.downcase : nil
action = $actions.find {|act| act[:name] == action_name }
unless action
	print "Must specify an action from the following list: %s\nSee --help for details.\n" % $actions.map{|act| act[:name] }.join(', ')
	exit 1
end

# execute the desired action
action[:proc].call(*ARGV)
