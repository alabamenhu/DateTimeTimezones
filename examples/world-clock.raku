use DateTime::Timezones;
sub MAIN (**@timezones) {
    react whenever Supply.interval(1) {
        my $time = DateTime.new: now;
        say "  {.hh-mm-ss} {.tz-abbr}\t{.olson-id}"
            for @timezones.map({$time.in-timezone: $_});
        print "\x001b[F" xx @timezones;
    }
}