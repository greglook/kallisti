# A class representing a waypoint marker tying together textual media with a time and geocoordinate


module Kallisti
class Voyage
	attr_accessor :name, :desc, :author
	attr_reader :legs, :waypoints
	attr_reader :distance, :duration
	
	
	# construct a new voyage object
	def initialize(name, desc, author = nil)
		@name = name
		@desc = desc
		@author = author
		
		@legs = []        # Kallisti::Leg
		@waypoints = []   # Kallisti::Waypoint
		@distance = 0     # voyage distance in nmi
		@duration = 0     # voyage length in seconds
	end
	
	
	# add a new leg to this voyage
	def add_leg(leg)
		raise "Cannot add nil leg to voyage" unless leg
		raise "A leg with that name already exists" if @legs.find {|l| l.name == leg.name }
		raise "This leg would overlap another" if @legs.find {|l| l.contains?(leg.from) or l.contains?(leg.to) }
		
		@legs << leg
		@legs.sort!
		true
	end
	
	
	# add a new waypoint object to this voyage
	def add_point(point, ignore_duplicate = false)
		raise "Cannot add nil point to voyage" unless point
		return false if not ignore_duplicate and @waypoints.find {|p| point.duplicates? p }

		@waypoints << point
		@waypoints.sort!
		true
	end
	
	
	# return a string representation of this voyage
	def to_s
		s = "=== #{@name} ===\n#{@desc}\n"
		s << "Author: #{@author}\n" if @author
		
		s << "\n"
		
		unless @waypoints.empty?
			s << "Voyage begun %s\n" % @waypoints.first.time.strftime('%Y-%m-%d')
			s << "Last updated %s\n" % @waypoints.last.time.strftime('%Y-%m-%d')
			s << "%.2f nautical miles covered in %d days\n\n" % [@distance, @duration/86400]
		end
		
		s << "%d waypoints in %d legs" % [@waypoints.size, @legs.size]
		
		s
	end
	
	
	# (re)calculates route statistics after new data is added
	def update!
		return if @waypoints.empty?
		
		# sort waypoints by time
		@waypoints.sort!
		
		@distance = 0.0
		@duration = @waypoints.last.time - @waypoints.first.time
		
		# these waypoint references only ever point to records with known (rather than interpolated) coordinates
		prev_point = nil
		next_point = nil
		
		# loop through points
		@waypoints.each_with_index do |point, i|
			
			day = ((point.time - @waypoints.first.time)/(24*60*60)).floor
			
			# if source is :spot or :waypoint set title and text to calculated value
			if [:waypoint, :spot].include? point.source
				
				distance = prev_point ? point.location - prev_point.location : 0.0
				elapsed = prev_point ? point.time - prev_point.time : 0.0
				speed = ( elapsed > 0 ) ? distance/(elapsed/3600) : nil
				
				@distance += distance
				
				point.title = "Day %d" % day
				point.text = "Traveled %.1f nmi at %.1f knots" % [distance, speed] if speed
				
				
			# if source is :sailmail or :log or :message interpolate coordinate from surrounding values
			elsif [:message, :log, :sailmail].include? point.source
				
				# try to find the next point with a known location
				next_point = @waypoints.slice((i + 1)..@waypoints.length).detect{|p| p.known_location? } if next_point.nil? or ( next_point < point )
				
				# interpolate with available data
				if prev_point and next_point
					
					p = (point.time - prev_point.time)/(next_point.time - prev_point.time)
					
					point.location = Geocoordinate.new(
						prev_point.location.latitude + p*(next_point.location.latitude - prev_point.location.latitude),
						prev_point.location.longitude + p*(next_point.location.longitude - prev_point.location.longitude)
					)
					
				elsif prev_point or next_point
					
					point.location = (prev_point or next_point).location.clone
					
				end
				
				# automatically set log titles
				point.title = "Ship's Log Day %d" % day if point.source == :log
				
				
			# unknown point source!
			else
				raise "Unkown point source #{point.source}"
			end
			
			# update prev_point
			prev_point = point if point.known_location?
			
		end
	end
	
end
end

