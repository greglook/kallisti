# Kallisti

This script manages a local data store of geographic waypoints and associated
communications information. Originally, I wrote this for a friend's sailing trip
across the Pacific Ocean.

In order to operate, the script needs to know two things, the path to a
YAML configuration file and the path to the YAML data file. These are
provided by the --config and --file arguments, respectively.

## Usage

The script can perform various actions, supplied after global arguments.

`configure <key> <value>`
    Sets a configuration value in the config file.

`new <name> <desc> [author]`
    Creates a new Voyage and writes it to the data file.

`show`
    Prints out a summary of the entire voyage.

`show-legs [from] [to]`
    Prints out information about the voyage legs.
    Supply times for the 'from' and 'to' arguments to restrict to a specific
    timespan.

`show-points [from] [to]`
     Prints the voyage points. Supply times for the 'from' and 'to' arguments
     to restrict to a specific timespan. Long message bodies will be truncated
     unless the --full option is used.

`add-leg <name> <start> <end>`
     Adds a new leg to the voyage. Legs are named timespans that group
     different sections of the trip together. Legs cannot overlap in time and
     should not have gaps between them for best results.

`add-waypoint <time> <latitude> <longitude>`
     Adds a waypoint to the data set. A waypoint is a timestamped geographic
     coordinate. The title and text are set programatically.

`add-message <time> <title> <text>`
     Adds a new message to the data set. A message is a timestamped title and
     text body. The location is interpolated based on the time.

`add-log <time> <text>`
     Adds a new log entry to the data set. Logs are similar to messages except
     that the title is set automatically and a different icon is used.

`update-spots`
     Connects to the configured mail account to check for new SPOT messages.
     SPOTs are a special type of waypoint.

`update-sailmail`
     Connects to the configured mail account to check for new SailMail messages.
     SailMails are a special type of message.

`update`
    Equivalent to the actions 'update-spots', 'update-sailmail', then 'show'.

`kml [style]`
    Outputs the dataset as a kml file.
    The 'style' argument should be either 'map' or 'earth' depending on whether
    the file will be imported into Google Maps or Google Earth. The 'earth'
    style includes categorization by leg and timestamp information.
