use DateTime::Timezones;
sub MAIN (**@timezones where * > 0) {
    react whenever Supply.interval(1) {
        my $time = DateTime.new: now;
        say "  {.hh-mm-ss} {.tz-abbr}\t{.olson-id}"
            for @timezones.map({$time.in-timezone: $_});
        print "\x001b[F" xx @timezones;
    }
}

sub USAGE {
    print q:to/END/
        Usage: raku world-clock.raku Olson/ID Olson/ID …

        Each Olson ID should be in the format of Region/City.
        Updates with the time for the given zones each second.
        END
}