sub MAIN (**@timezones) {
    react {
        whenever Supply.interval(1) {
            use DateTime::Timezones;
            my $time = DateTime.new: now;
            say "  {.hh-mm-ss} {.tz-abbr} - {.olson-id}"
                for @timezones.map({$time.in-timezone: $_});
            print "\x001b[F" xx @timezones;
        }
    }
}