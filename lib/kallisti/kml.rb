# Patches other Kallisti classes with KML formatting methods.


# format a number with thousands separators
def separateKs(n) n.to_i.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,") end


class Time
	# renders this Time as a kml-formatted time string
	def to_kml
		self.strftime("%Y-%m-%dT%H:%M:%SZ")
	end
end


class Geocoordinate
	# renders this Geocoordinate as a kml <Point>
	def to_kml(indent = 0)
		"%s<Point><coordinates>%f,%f</coordinates></Point>" % ["\t" * indent, @longitude, @latitude]
	end
end


class Kallisti::Leg
	# renders this Leg as a kml folder structure
	def to_kml(waypoints, indent = 0, options = {})
		i = "\t" * indent
		ii = i + "\t"
		iii = ii + "\t"
		
		"#{i}<Folder>\n" <<
			"#{ii}<name><![CDATA[#{@name}]]></name>\n" <<
			"#{ii}<open>0</open>\n" <<
			( options[:time_info] ? "#{ii}<TimeSpan>\n#{iii}<begin>#{@from.to_kml}</begin>\n#{iii}<end>#{@to.to_kml}</end>\n#{ii}</TimeSpan>\n" : "" ) <<
			waypoints.select{|point| self.contains? point.time }.map{|point| point.to_kml(indent + 1, options) }.join <<
		"#{i}</Folder>\n"
	end
end


class Kallisti::Waypoint
	# renders this Waypoint as a kml <Placemark>
	def to_kml(indent = 0, options = {})
		i = "\t" * indent
		ii = i + "\t"
		
		"#{i}<Placemark>\n" <<
			"#{ii}<name><![CDATA[#{@title}]]></name>\n" <<
			("#{ii}<styleUrl>#%s</styleUrl>\n" % case @source
				when :waypoint, :spot then 'location'
				when :message, :sailmail then 'message'
				when :log then 'ship_log' end) <<
			"#{ii}#{@location.to_kml}\n" <<
			( options[:time_info] ? "#{ii}<TimeStamp><when>#{@time.to_kml}</when></TimeStamp>\n" : "" ) <<
			( @text ? "#{ii}<description><![CDATA[#{@text}]]></description>\n" : "" ) <<
		"#{i}</Placemark>\n"
	end
end


class Kallisti::Voyage
	# renders this Voyage as a kml document
	def to_kml(options = {})
		kml_style_string = "\t<Style id=\"%s\"><IconStyle><Icon><href>%s</href></Icon></IconStyle></Style>\n"
		
		kml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <<
		"<kml xmlns=\"http://www.opengis.net/kml/2.2\">\n" <<
		"<Document>\n" <<
			
			# metadata
			"\t<name>#{@name}</name>\n" <<
			"\t<description>#{@description}</description>\n" <<
				( @author ? "\t<atom:author>#{@author}</atom:author>\n" : "" ) <<
			
			# icon styles
			(kml_style_string % ['location', 'http://maps.google.com/mapfiles/kml/shapes/sailing.png']) <<
			(kml_style_string % ['message', 'http://maps.google.com/mapfiles/kml/shapes/post_office.png']) <<
			(kml_style_string % ['ship_log', 'http://maps.google.com/mapfiles/kml/shapes/man.png']) << "\n"
			
			# each leg is a folder
			if options[:leg_folders]
				
				# print the folders and all points they contain, respectively
				kml << @legs.map{|leg| leg.to_kml(@waypoints, 1, options) }.join("\n")
				
				# print points not in any leg
				kml << @waypoints.select{|point| @legs.find{|leg| leg.contains? point.time }.nil? }.map{|point| point.to_kml(1, options) }.join
				
			# flat list of points
			else
				
				kml << @waypoints.map{|point| point.to_kml(1, options) }.join
				
			end
			
			# add overall route between locations
			kml << "\n\t<Placemark>\n" <<
				"\t\t<name>Route</name>\n" <<
				# <styleUrl>
				( options[:time_info] ? ( "\t\t<TimeSpan>\n\t\t\t<begin>#{@waypoints.first.time.to_kml}</begin>\n\t\t\t<end>#{@waypoints.last.time.to_kml}</end>\n\t\t</TimeSpan>\n" ) : "" ) <<
				("\t\t<description>%s nmi</description>" % separateKs("%.2f" % @distance)) <<
				("\t\t<LineString>\n\t\t\t<coordinates>%s</coordinates>\n\t\t</LineString>\n" % @waypoints.select{|p| p.known_location? }.map{|point| "%f,%f" % [point.location.longitude, point.location.latitude] }.join(' ')) <<
			"\t</Placemark>\n" <<
			
		"</Document>\n" <<
		"</kml>"
	end
end

