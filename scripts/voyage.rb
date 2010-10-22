#!/usr/bin/ruby

# This script manages a local data store of waypoints


# this hash holds purely runtime options that should not be persisted
$options = {
	:verbose => false,
	:config_file => "config.yml",
	:merge_all => false,
	:action => nil,
	:ignore_duplication => false,
	:time_info => false,
	:leg_folders => false,
}

# this hash holds persistent configuration for the script
$config = { }

# the actual waypoint set
$waypoints = [ ]


class Leg
	include Comparable
	
	attr_reader :name, :from, :to
	
	def initialize(name, from, to)
		@name = name
		@from = from
		@to = to
	end
	
	def contains?(time)
		( @from <= time ) and ( time < @to )
	end
	
	# waypoints are ordered by time
	def <=>(other)
		@from <=> other.from
	end
	
end


#############################
#     Utility Functions     #
#############################

# add a parsing method to Time
require 'time'
#def Time.parse(string)
#	
#	return nil if string.nil?
#	
#	d = Date._parse(string)
#	t = Time.gm(d[:year], d[:mon], d[:mday], d[:hour], d[:min], d[:sec])
#	t -= d[:offset] if d[:offset]
#	
#	return t
#	
#end


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


# check whether the a point with the given source and time will be a duplicate
def will_duplicate?(source, time)
	range = (time - 300)..(time + 300)
	$waypoints.detect { |point| ( source == point.source ) and ( range === point.time ) }
end





#################################
#     Persistence Functions     #
#################################

require 'waypoint'

# try to load configuration from a file
def load_config
	if $options[:config_file] and File.exists? $options[:config_file] then
		profile "Loading configuration from " << $options[:config_file] do
			config_file = nil
			File.open($options[:config_file]) { |file| config_file = YAML::load file }
			if config_file then
				config_file.each { |key, value| $config[key] = value unless $config.has_key? key }
			else
				print " unable to load configuration from specified file!\n"
				exit 1
			end
		end
	end
end


# load waypoint data from file
def load_waypoints
	
	# ensure path was specified
	return if $config[:data_file].nil?
	
	# load if exists
	if File.exists? $config[:data_file] then
		profile "Loading dataset from " << $config[:data_file] do
			File.open($config[:data_file]) { |file| $waypoints = YAML::load file }
			unless $waypoints then
				print " unable to load data from specified file!\n"
				exit 1
			end
		end
	end
	
end


# save waypoint data to file
def save_waypoints
	
	# ensure path was specified
	if $config[:data_file].nil? then
		print "You must specify a data file with --file or through a config file!\n"
		exit 1
	end
	
	profile "Saving dataset to " << $config[:data_file] do
		File.open($config[:data_file], 'w') { |file| file << $waypoints.to_yaml }
	end
	
end



##########################
#     IMAP functions     #
##########################

require 'net/imap'

# open IMAP connection to check mail
def open_imap
	raise "IMAP connection is already open!" if $imap
	raise "--mail-server must be set!" unless $config[:mail_server]
	raise "--mail-account must be set!" unless $config[:mail_account]
	raise "--mail-password must be set!" unless $config[:mail_password]

	
	profile("Signing in to mail account %s" % $config[:mail_account]) do
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
def merge_spots
	raise "IMAP connection must be open!" unless $imap
	raise "--spot-address must be set!" unless $config[:spot_address]
	
	# restrict fetches to after this date
	last_spot = $waypoints.reverse.detect { |point| point.source == :spot }
	last_updated = (last_spot.nil? or $options[:merge_all]) ? Time.gm(1970, 1, 2) : last_spot.time
	last_updated = "%d-%s-%d" % [last_updated.day, Net::IMAP::DATE_MONTH[last_updated.month - 1], last_updated.year]
	
	# fetch mail ids
	mails = profile("Checking for new SPOT messages since " << last_updated) { $imap.search(['SEEN', 'FROM', $config[:spot_address], 'SINCE', last_updated]) }
	
	# return if no updates
	return unless mails and not mails.empty?
	
	# fetch mail data
	mails = profile("Fetching %d messages" % mails.length) { mails.collect { |id| $imap.fetch(id, ['ENVELOPE', 'BODY[TEXT]'])[0] } }
	
	# process spot mails
	profile("Processing messages") do mails.each do |mail|
		
		subject = mail.attr['ENVELOPE'].subject
		body = mail.attr['BODY[TEXT]']
		
		# parse out information
		time = Time.parse(body.scan(/Time:(.+?)\s*\r\n/)[0][0])
		latitude = body.scan(/Latitude:(\-?[0-9]+\.[0-9]+)/)[0][0].to_f
		longitude = body.scan(/Longitude:(\-?[0-9]+\.[0-9]+)/)[0][0].to_f
		message = body.match(/Message:Everything is OK/) ? 'OK' : 'SOS'
		
		raise "Could not parse time from SPOT message body: " << body unless time.is_a? Time
		raise "Could not parse latitude from SPOT message body: " << body unless latitude.is_a? Float
		raise "Could not parse longitude from SPOT message body: " << body unless longitude.is_a? Float
		
		# check if there's already a :spot within ~5 minutes of this one to dedup
		next if will_duplicate?(:spot, time)
		
		# add :spot to waypoints
		$waypoints << Waypoint.new(:spot, time, Geocoordinate.new(latitude, longitude))
		
	end end
	
end


# fetch new SailMail messages
def merge_sailmails
	raise "IMAP connection must be open!" unless $imap
	raise "--sailmail-address must be set!" unless $config[:sailmail_address]
	
	# restrict fetches to after this date
	last_sailmail = $waypoints.reverse.detect { |point| point.source == :sailmail }
	last_updated = (last_sailmail.nil? or $options[:merge_all]) ? Time.gm(1970, 1, 2) : last_sailmail.time
	last_updated = "%d-%s-%d" % [last_updated.day, Net::IMAP::DATE_MONTH[last_updated.month - 1], last_updated.year]
	
	# fetch mail ids
	mails = profile("Checking for new SailMail messages since " << last_updated) { $imap.search(['SEEN', 'FROM', $config[:sailmail_address], 'SINCE', last_updated]) }
	
	# return if no updates
	return unless mails and not mails.empty?
	
	# fetch mail data
	mails = profile("Fetching %d messages" % mails.length) { mails.collect { |id| $imap.fetch(id, ['ENVELOPE', 'BODY[TEXT]'])[0] } }
	
	# process spot mails
	profile("Processing messages") do mails.each do |mail|
		
		subject = mail.attr['ENVELOPE'].subject
		body = mail.attr['BODY[TEXT]']
		time = Time.parse(mail.attr['ENVELOPE'].date)
		
		# trim signature from mail and obscure address
		body = body.split('-------------------------------------------------')[0]
		body.gsub!(Regexp.new($config[:sailmail_address], Regexp::IGNORECASE), '--- ADDRESS REDACTED ---')
		body.gsub!(/=\r\n/, '')
		
		raise "Could not parse time from SPOT message body: " << body unless time.is_a? Time
		
		# check if there's already a :sailmail within ~5 minutes of this one to dedup
		next if will_duplicate?(:sailmail, time)
		
		# add :sailmail to waypoints
		$waypoints << Waypoint.new(:sailmail, time, nil, subject, body.chomp)
		
	end end
	
end



##################################
#     Statistics calculation     #
##################################

# calculate route statistics
def calculate_statistics
	
	return if $waypoints.empty?
	
	profile("Calculating route statistics") do
		
		# reset overall statistics
		$route_distance = 0.0
		$route_time = 0.0
		$route_speed = nil
		$route_speed_max = nil
		
		# sort waypoints by time
		$waypoints.sort!
		
		# these waypoint references only ever point to records with known (rather than interpolated) coordinates
		prev_point = nil
		next_point = nil
		
		# loop through points
		$waypoints.each_with_index do |point, i|
			
			day = ((point.time - $waypoints[0].time)/(24*60*60)).floor
			
			# if source is :spot or :waypoint set title and text to statistics
			if [:waypoint, :spot].include? point.source then
				
				distance = prev_point ? point.location - prev_point.location : 0.0
				elapsed = prev_point ? point.time - prev_point.time : 0.0
				speed = ( elapsed > 0 ) ? distance/(elapsed/3600) : nil
				
				$route_distance += distance
				$route_time += elapsed
				$route_speed_max = speed if $route_speed_max.nil? or ( speed > $route_speed_max )
				
				point.title = format("Day %d", day)
				point.text = format("Traveled %.1f nmi at %.1f knots", distance, speed) if speed
				
				
			# if source is :sailmail or :log or :message interpolate coordinate from surrounding values
			elsif [:message, :log, :sailmail].include? point.source then
				
				# try to find the next point with a known location
				if next_point.nil? or ( next_point < point ) then
					next_point = nil
					j = i + 1
					while($waypoints[j]) do
						if $waypoints[j].known_location? then
							next_point = $waypoints[j]
							break
						end
						j += 1
					end
				end
				
				# interpolate with available data
				if prev_point and next_point then
					
					p = (point.time - prev_point.time)/(next_point.time - prev_point.time)
					
					point.location = Geocoordinate.new(
						prev_point.location.latitude + p*(next_point.location.latitude - prev_point.location.latitude),
						prev_point.location.longitude + p*(next_point.location.longitude - prev_point.location.longitude)
					)
					
				elsif prev_point or next_point then
					
					point.location = (prev_point or next_point).location.clone
					
				end
				
				# automatically set log titles
				point.title = "Ship's Log Day %d" % day if point.source == :log
				
				
			# unknown point source!
			else
				raise "Unkown point source " << point.source
			end
			
			# update prev_point
			prev_point = point if point.known_location?
			
		end
		
		$route_speed = ( $route_time > 0 ) ? $route_distance/($route_time/3600.0) : nil
		
	end
end



#############################
#     Output Formatting     #
#############################

# format a number with thousands separators
def separateKs(n) n.to_i.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,") end


# show waypoints, optionally specifying time constraints
def show_waypoints(from = Time.at(0), to = Time.now)
	raise "from must be a Time!" unless from.is_a? Time
	raise "to must be a Time!" unless to.is_a? Time
	
	range = from..to
	$waypoints.each_with_index { |point, i| print("%3d. %s\n" % [i, point]) if range === point.time }
	print("%s\nRoute: %s nmi at an average speed of %.2f knots\n" % ['-'*60, separateKs($route_distance), $route_speed]) if $route_speed
end


# convert a time to KML time value
class Time
	def to_kml_time
		self.strftime("%Y-%m-%dT%H:%M:%SZ")
	end
end


class String
	def indent(i = 1)
		("\t"*i) << self
	end
end


# represent a Geocoordinate as a kml <Point>
class Geocoordinate
	def to_kml_point(indent = 0)
		("<Point><coordinates>%f,%f</coordinates></Point>" % [@longitude, @latitude]).indent(indent)
	end
end


# build a string representing this waypoint as a KML <Placemark>
class Waypoint
	def to_kml_placemark(indent = 0)
		t = Proc.new {|level, string| ("\t"*(indent + level)) << string << "\n" }
		i = Proc.new {|s| t[0, s] }
		ii = Proc.new {|s| t[1, s] }
		iii = Proc.new {|s| t[2, s] }
		
		i["<Placemark>"] <<
			ii["<name><![CDATA[%s]]></name>" % @title] <<
			ii["<styleUrl>#%s</styleUrl>" % case @source
				when :waypoint, :spot then 'location'
				when :message, :sailmail then 'message'
				when :log then 'ship_log' end ] <<
			( @text ? ii["<description><![CDATA[%s]]></description>" % @text] : "" ) <<
			( $options[:time_info] ? ii["<TimeStamp>"] <<
				iii["<when>%s</when>" % @time.to_kml_time] <<
			ii["</TimeStamp>"] : '' ) <<
			@location.to_kml_point(indent+1) << "\n" <<
		i["</Placemark>"]
	end
end


# Print a leg as a KML folder structure
class Leg
	def to_kml_folder(indent = 0)
		t = Proc.new {|level, string| ("\t"*(indent + level)) << string << "\n" }
		i = Proc.new {|s| t[0, s] }
		ii = Proc.new {|s| t[1, s] }
		iii = Proc.new {|s| t[2, s] }
		
		i["<Folder>"] <<
			ii["<name><![CDATA[%s]]></name>" % @name] <<
			ii["<open>0</open>"] <<
			( $options[:time_info] ? ( ii["<TimeSpan>"] <<
				iii["<begin>%s</begin>" % @from.to_kml_time] <<
				iii["<end>%s</end>\n" % @to.to_kml_time] <<
			ii["</TimeSpan>"] ) : '' ) <<
			$waypoints.select{|point| contains? point.time }.map(&:to_kml_placemark).join <<
		i["</Folder>"]
	end
end


# get a kml <Placemark> representing the entire route
def get_kml_route(indent = 0)
	t = Proc.new {|level, string| ("\t"*(indent + level)) << string << "\n" }
	i = Proc.new {|s| t[0, s] }
	ii = Proc.new {|s| t[1, s] }
	iii = Proc.new {|s| t[2, s] }
	
	i["<Placemark>"] <<
		ii["<name>Route</name>"] <<
		# <styleUrl>
		( $options[:time_info] ? ( ii["<TimeSpan>"] <<
			iii["<begin>%s</begin>" % $waypoints.first.time.to_kml_time] <<
			iii["<end>%s</end>" % $waypoints.last.time.to_kml_time] <<
		ii["</TimeSpan>"] ) : '' ) <<
		ii["<description>%s nmi\nAverage speed: %.2f knots\nTop speed: %.2f knots</description>" % [separateKs("%.2f" % $route_distance), $route_speed, $route_speed_max]] <<
		ii["<LineString>"] <<
			iii["<coordinates>%s</coordinates>" % $waypoints.select(&:known_location?).map{|point| "%f,%f" % [point.location.longitude, point.location.latitude] }.join(' ')] <<
		ii["</LineString>"] <<
	i["</Placemark>"]
end


# print a kml document of the dataset
def print_kml_document
	print "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	print "<kml xmlns=\"http://www.opengis.net/kml/2.2\">\n"
	print "<Document>\n"
			
		# metadata
		print "<name>Kallisti's Voyage</name>\n"
		print "<atom:author>Greg Look</atom:author>\n"
		print "<description>A map of Kevin and Ted's journey around the world!</description>\n"
		
		# icon styles
		kml_style_string = Proc.new {|id, icon_href| "<Style id=\"%s\"><IconStyle><Icon><href>%s</href></Icon></IconStyle></Style>\n" % [id, icon_href] }
		print kml_style_string['location', 'http://maps.google.com/mapfiles/kml/shapes/sailing.png']
		print kml_style_string['message', 'http://maps.google.com/mapfiles/kml/shapes/post_office.png']
		print kml_style_string['ship_log', 'http://maps.google.com/mapfiles/kml/shapes/man.png']
		
		print "\n"
		
		# each leg is a folder
		if $options[:leg_folders] then
			
			# print the folders and all points they contain, respectively
			print $config[:legs].map(&:to_kml_folder).join("\n")
			
			# print points not in any leg
			print $waypoints.select{|point| $config[:legs].find{|leg| leg.contains? point.time }.nil? }.map(&:to_kml_placemark).join
			
		# flat list of points
		else
			
			print $waypoints.map(&:to_kml_placemark).join
			
		end
		
		print "\n"
		
		# add overall route between locations
		print get_kml_route
		
	print "</Document>\n"
	print "</kml>"
end



###########################
#     Action Closures     #
###########################

$actions = { }

# print current configuration
$actions['config'] = {
	:desc => "Prints out the current configuration; use this to generate config files loadable with --config",
	:proc => Proc.new do
		print $config.to_yaml
	end
}

# print out current dataset
$actions['show'] = {
	:args => "[from time] [to time]",
	:desc => "Prints out the waypoint dataset",
	:proc => Proc.new do |from, to|
		from = from ? Time.parse(from) : Time.at(0)
		to = to ? Time.parse(to) : Time.now
		load_waypoints
		calculate_statistics
		show_waypoints(from, to)
	end
}

# print the dataset as a KML file
$actions['kml'] = {
	:desc => "Output a KML file of the complete dataset",
	:proc => Proc.new do
		load_waypoints
		calculate_statistics
		print_kml_document
	end
}

# add a leg from options
$actions['leg'] = {
	:args => "<name> <from time> <to time>",
	:desc => "Add a leg to the configuration and prints it",
	:proc => Proc.new do |name, from, to|
		raise "Must supply a name argument!" unless name
		raise "Must supply a from time argument!" unless from
		raise "Must supply a to time argument!" unless to
		
		from = Time.parse(from)
		to = Time.parse(to)
		
		$config[:legs] ||= [ ]
		
		raise "A leg with that name already exists!" if $config[:legs].detect { |leg| leg.name == name }
		raise "This leg would overlap another!" if $config[:legs].detect { |leg| leg.contains?(from) or leg.contains?(to) }
		
		$config[:legs] << Leg.new(name, from, to)
		$config[:legs].sort!
		
		print $config.to_yaml
	end
}

# manually add a waypoint to the dataset
$actions['waypoint'] = {
	:args => "<time> <latitude> <longitude>",
	:desc => "Manually add a waypoint to the dataset",
	:proc => Proc.new do |time, latitude, longitude|
		raise "Must supply a time argument!" unless time
		raise "Must supply a latitude argument!" unless latitude
		raise "Must supply a longitude argument!" unless longitude
		
		load_waypoints
		time = Time.parse(time)
		latitude = latitude.to_f
		longitude = longitude.to_f
		
		if will_duplicate?(:waypoint, time) and not $options[:ignore_duplication] then
			print "There is already a waypoint within 5 minutes of this time!\nPoint will NOT be added to prevent duplication. To override this, use --ignore-duplication\n"
			exit 1
		end
		
		$waypoints << Waypoint.new(:waypoint, time, Geocoordinate.new(latitude, longitude))
		save_waypoints
	end
}

# manually add a message to the dataset
$actions['message'] = {
	:args => "<time> <title> <text>",
	:desc => "Manually add a message to the dataset",
	:proc => Proc.new do |time, title, text|
		raise "Must supply a time argument!" unless time
		raise "Must supply a title argument!" unless title
		raise "Must supply a text argument!" unless text
		
		load_waypoints
		time = Time.parse(time)
		
		if will_duplicate?(:message, time) and not $options[:ignore_duplication] then
			print "There is already a message within 5 minutes of this time!\nPoint will NOT be added to prevent duplication. To override this, use --ignore-duplication\n"
			exit 1
		end
		
		$waypoints << Waypoint.new(:message, time, nil, title, text)
		save_waypoints
	end
}

# manually add a log entry to the dataset
$actions['log'] = {
	:args => "<time> <text>",
	:desc => "Manually add a ship log entry to the dataset",
	:proc => Proc.new do |time, text|
		raise "Must supply a time argument!" unless time
		raise "Must supply a text argument!" unless text
		
		load_waypoints
		time = Time.parse(time)
		title = "Ship's Log"
		
		if will_duplicate?(:log, time) and not $options[:ignore_duplication] then
			print "There is already a log entry within 5 minutes of this time!\nPoint will NOT be added to prevent duplication. To override this, use --ignore-duplication\n"
			exit 1
		end
		
		$waypoints << Waypoint.new(:log, time, nil, title, text)
		save_waypoints
	end
}

# add SPOT messages
$actions['spot'] = {
	:desc => "Connect to the configured mail account to check for SPOT messages",
	:proc => Proc.new do
		load_waypoints
		open_imap
		merge_spots
		close_imap
		save_waypoints
	end
}

# add SailMail messages
$actions['sailmail'] = {
	:desc => "Connect to the configured mail account to check for SailMail messages",
	:proc => Proc.new do
		load_waypoints
		open_imap
		merge_sailmails
		close_imap
		save_waypoints
	end
}

# do dataset calculations
$actions['calculate'] = {
	:desc => "(Re)calculates statistics for the waypoint dataset",
	:proc => Proc.new do
		load_waypoints
		calculate_statistics
		save_waypoints
	end
}

# run a full update
$actions['update'] = {
	:desc => "Equivalent to the actions 'spot', 'sailmail', 'calculate', then 'show'",
	:proc => Proc.new do
		load_waypoints
		open_imap
		merge_spots
		merge_sailmails
		close_imap
		calculate_statistics
		save_waypoints
		show_waypoints
	end
}




########################
#     Command Line     #
########################

require 'optparse'

# set up command-line options
option_parser = OptionParser.new do |opts|
	
	opts.banner = "Usage: points.rb [options...] <action> [action parameters...]\n" <<
		"\nActions\n" <<
		($actions.collect { |name, action|
			"    " << name << " " << (action[:args] or "") << "\n        " << action[:desc]
		}).join("\n")
	
	opts.separator ""
	opts.separator "General options"
	opts.on('-f', '--file FILE', "File containing waypoint dataset, or path to save new set") {|file| $config[:data_file] = file }
	opts.on('-c', '--config FILE', "Use the given file for configuration") {|file| $options[:config_file] = file }
	opts.on('-v', '--verbose', "Output detailed processing information") { $options[:verbose] = true }
	opts.on('-h', '--help', "Display this screen") { print opts; exit }
	
	opts.separator ""
	opts.separator "SPOT & SailMail configuration"
	opts.on('--mail-server HOST',         "IMAP host to connect to") {|host| $config[:mail_server] = host }
	opts.on('--mail-account ACCOUNT',     "Mail account name") {|account| $config[:mail_account] = account }
	opts.on('--mail-password PASSWORD',   "Mail account password") {|password| $config[:mail_password] = password }
	opts.on('--spot-address ADDRESS',     "SPOT email adddress") {|address| $config[:spot_address] = address }
	opts.on('--sailmail-address ADDRESS', "SailMail email address") {|address| $config[:sailmail_address] = address }
	opts.on('--merge-all',                "If set, will attempt to merge all SPOT and SailMail messages found rather than only recent ones") { $options[:merge_all] = true }
	
	opts.separator ""
	opts.separator "Misc options"
	opts.on('--ignore-duplication',       "Ignore duplication warnings when adding points to the dataset") { $options[:ignore_duplication] = true }
	opts.on('--[no-]time-info',           "Include time information in generated output such as KML") {|v| $options[:time_info] = v }
	opts.on('--[no-]leg-folders',         "Organize the waypoints into folders by leg in generated output such as KML") {|v| $options[:leg_folders] = v }
	
end

# parse command line
option_parser.parse!

# try to load the file in :use_config to fill out configuration
load_config

# get action from first argument
$options[:action] = ( ARGV.length > 0 ) ? ARGV.shift.downcase : nil
unless $actions.has_key? $options[:action] then
	print "Must specify an action from the following list: " << $actions.keys.join(', ') << ". See --help for details.\n"
	exit 1
end

# execute the desired action
$actions[$options[:action]][:proc].call(*ARGV)
