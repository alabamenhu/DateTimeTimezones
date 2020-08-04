unit module Timezones;

role TimezoneAware[$olson = "Etc/GMT", $abbr = "GMT", $dst = False] {
    method olson-id   (-->  Str) { $olson }
    method tz-abbr (-->  Str) { $abbr  }
    method is-dst  (--> Bool) { $dst   }
}

# Once because double wrapping would be bad and we're evil enough.
once DateTime.^find_method('new').wrap(
    method (|c) {
        # At some point we need to call the original function.
        # This feels a bit hacky, but it works.  A dynamic value anywhere
        # in the call chain with this name could throw this off, but I'm
        # not sure we can guarantee that it will come X levels up.
        if CALLERS::<$*USE-ORIGINAL-DATETIME-NEW> {
            return callwith self, |c.list, |c.hash.pairs.grep(*.key ne 'olson');
        }

        my $*USE-ORIGINAL-DATETIME-NEW = True;
        my \original = callwith self, |c;

        # Next, we determine what timezone we'll use.
        # Anything the caller gives us takes priority, of course.
        # Otherwise, check and see if the UserTimezone module is installed
        # and use its results.  Failing that, go with Etc/GMT

        my $tz-id;
        with c.hash<olson> {
            $tz-id = $_;
        } else {
            try require ::('Intl::UserTimezone');
            $tz-id = ::('Intl::UserTimezone') !~~ Failure
                ?? ::('Intl::UserTimezone::EXPORT::DEFAULT::&user-timezone')()
                !! 'Etc/GMT';
        }

        use DateTime::Timezones::Routines;
        my $tz = get-timezone-data($tz-id.chomp);
        my $time = localtime $tz, original.posix, 0; # TM format, not Raku DateTime!


        # Finally the magic! Return the moment but with an adjusted offset, mixing in the awareness
        my \tz-aware = original.in-timezone($time.gmt-offset)
            but TimezoneAware[
                $tz-id.chomp,   # The Olson ID (e.g. America/New_York)
                $time.tz-abbr,  # The nominal zone (e.g. EST/EDT)
                $time.dst.Bool  # Daylight saving time status.
            ];
        tz-aware.^set_name('DateTime');
        tz-aware
    }
);