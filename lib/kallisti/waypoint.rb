# A class representing a waypoint marker tying together textual media with a time and geocoordinate


require 'geocoordinate'


module Kallisti
class Waypoint
	include Comparable
	
	SOURCES = [
		:waypoint,    # manual waypoint entry, time and location must be provided
		:message,     # manual message entry, time must be provided, location is interpolated
		:log,         # manual ship's log entry, time must be provided, location / title are computed
		:spot,        # parsed from a SPOT email, time and location parsed
		:sailmail,    # parsed from a SailMail email, time is parsed, location is interpolated
	]
	
	attr_reader :source, :time
	attr_accessor :location, :title, :text
	
	
	# construct a new waypoint with a time and location
	def initialize(source, time, location = nil, title = nil, text = nil)
		
		# always require correct source and times
		raise "source must be one of " + SOURCES.join(', ') + "!" unless SOURCES.include? source
		raise "time must be a Time or Numeric!" unless time.is_a? Time or time.is_a? Numeric
		
		# require coordinate except for :message and :sail_mail sources
		raise "location must be a Geocoordinate!" unless (location.nil? and [:message, :log, :sailmail].include? source) or location.is_a? Geocoordinate
		
		@source = source
		@time = Time.at(time).gmtime
		@location = location
		@title = title
		@text = text
		
	end
	
	
	# return a string representation of this waypoint
	def to_s
		format("(%+10.5f, %+10.5f) [%s%s] %s",
		    @location ? @location.latitude : -1.0,
		    @location ? @location.longitude : -1.0,
		    @time.strftime("%Y-%m-%d %H:%M:%S"),
		    @title.nil? ? "" : " - " + @title,
		    @text.nil? ? "" : @text.chomp)
	end
	
	
	# is the location known or interpolated?
	def known_location?
		( @source == :spot ) or ( @source == :waypoint )
	end
	
	
	# waypoints are ordered by time
	def <=>(other)
		@time <=> other.time
	end
	
	
	# duplicated waypoint detection (same category within 5 minutes)
	def duplicates?(other)
		window = (@time - 300)..(@time + 300)
		( @source == other.source ) and ( window === other.time )
	end
	
end
end

