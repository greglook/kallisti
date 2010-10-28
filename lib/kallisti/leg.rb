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
	
	def to_s
		days = (@to - @from)/86400
		"%s - %s %s (%d days)" % [@from.strftime('%Y-%m-%d'), @to.strftime('%Y-%m-%d'), @name, days]
	end
	
	# waypoints are ordered by time
	def <=>(other)
		@from <=> other.from
	end
end
end

