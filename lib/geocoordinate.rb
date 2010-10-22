#!/usr/bin/ruby

# A class to represent a geographic coordinate.

class Geocoordinate
	attr_accessor :latitude, :longitude
	
	# constructor
	def initialize(latitude = 0.0, longitude = 0.0)
		raise "latitude must be a Numeric!" unless latitude.is_a? Numeric
		raise "longitude must be a Numeric!" unless longitude.is_a? Numeric
		
		@latitude = latitude
		@longitude = longitude
		
		self.normalize
	end
	
	# normalize coordinate values
	def normalize
		
		@latitude %= 360.0
		@latitude -= 360.0 if ( @latitude > 180.0 )
		
		if ( @latitude > 90.0 ) then
			@latitude = 180 - @latitude
			@longitude += 180.0
		elsif ( @latitude < -90 ) then
			@latitude = 180.0 + @latitude
			@longitude += 180.0
		end
		
		@longitude %= 360.0
		@longitude -= 360.0 if ( @longitude > 180.0 )
		
	end
	
	# convert this point to a string
	def to_s
		format("%+.5f, %+.5f", @latitude, @longitude)
	end
	
	# convert location to degrees, minutes, and seconds
	def to_dms
		
		lat_degrees = @latitude.to_i
		lat_minutes = (60*@latitude.abs % 60).to_i
		lat_seconds = 60*60*@latitude.abs % 60
		
		lon_degrees = @longitude.to_i
		lon_minutes = (60*@longitude.abs % 60).to_i
		lon_seconds = 60*60*@longitude.abs % 60
		
		format("%+d%c %d' %.2f\", %+d%c %d' %.2f\"",
		    lat_degrees, 176, lat_minutes, lat_seconds,
		    lon_degrees, 176, lon_minutes, lon_seconds)
		
	end
	
	# convert two degrees, minutes, seconds tuples into a point
	def self.from_dms(lat_degrees, lat_minutes, lat_seconds, lon_degrees, lon_minutes, lon_seconds)
		
		latitude = lat_degrees + (lat_degrees/lat_degrees.abs)*(lat_minutes + lat_seconds/60)/60
		longitude = lon_degrees + (lon_degrees/lon_degrees.abs)*(lon_minutes + lon_seconds/60)/60
		
		self.new(latitude, longitude)
		
	end
	
	# compute the great-circle distance between two points
	def - (point)
		
		# check argument
		return nil if point.nil? or !point.respond_to?('latitude') or !point.respond_to?('longitude') or point.latitude.nil? or point.longitude.nil?
		
		# convert to radians
		lat1 = @latitude*Math::PI/180.0
		lat2 = point.latitude*Math::PI/180.0
		latd = (lat2 - lat1).abs
		
		lon1 = @longitude*Math::PI/180.0
		lon2 = point.longitude*Math::PI/180.0
		lond = (lon2 - lon1).abs
		
		# calculate central angle
		angle = Math.atan2(
		    Math.sqrt(
				(Math.cos(lat2)*Math.sin(lond))**2 +
				(Math.cos(lat1)*Math.sin(lat2) - Math.sin(lat1)*Math.cos(lat2)*Math.cos(lond))**2
			),
		    Math.sin(lat1)*Math.sin(lat2) + Math.cos(lat1)*Math.cos(lat2)*Math.cos(lond)
		)
		
		# convert to distance in nautical miles
		3440.07*angle
		
	end
	
	# clone this coordinate point
	def clone
		
		Geocoordinate.new(@latitude, @longitude)
		
	end
	
end
