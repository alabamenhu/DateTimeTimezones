use DateTime::Timezones;
use Test;

my $a = DateTime.new(now, :tz-id<America/New_York>);

#say $a.olson;
#say $a.tz-abbr;

#say $a.olson;
#say $a.year;
#say $a.day;

done-testing;
