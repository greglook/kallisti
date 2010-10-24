# A class to represent a group of waypoints in a voyage.

module Kallisti
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
end

