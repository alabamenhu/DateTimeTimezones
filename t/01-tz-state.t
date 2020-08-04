use DateTime::Timezones;

my $a = DateTime.new(now);
say $a.olson;
say $a.tz-abbr;
say $a.is-dst;
say $a;
say $a.yyyy-mm-dd, ' ', $a.hh-mm-ss;