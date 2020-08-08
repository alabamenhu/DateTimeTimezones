unit module Timezones;


role TimezoneAware[$olson = "Etc/GMT", $abbr = "GMT", $dst = False] {
    method olson-id   (-->  Str) { $olson }
    method tz-abbr (-->  Str) { $abbr  }
    method is-dst  (--> Bool) { $dst   }
}

use DateTime::Timezones::Routines;


# Once because double wrapping would be bad and we're evil enough.
# Also, because of callwith/callsame, we basically need to make this one big function
INIT DateTime.^find_method('new').wrap(
    method (|c) {

        # At some point we need to call the original function without
        # to get a plain old DateTime.  This distinguishes those calls
        # from user calls.
        if CALLERS::<$*USE-ORIGINAL-DATETIME-NEW> {
            return callwith self, |c;
        }

        # If given a gmt offset, life is easy.
        # If not, we need to calculate it and then life is kinda easy.
        #
        # There are two methods that allow construction directly from an integer value

        if c ~~ :(Instant:D $, *%)
        || c ~~ :(Int:D     $, *%) {
            # We can obtain an exact GMT-offset.
            my \arg    = c.list.head;
            my \posix  = arg ~~ Instant
                      ?? arg.to-posix.head
                      !! arg;

            my \tz-id  = c.hash<tz-id> // (c.hash<timezone> ~~ Str ?? c.hash<timezone> !! 'Etc/GMT');
            my \tz     = get-timezone-data tz-id;
            my \time   = localtime tz, posix;
                         # ^^ there is room for performance improvements here as
                         #    all we need to know is the offset at the given time.
                         #    This also calculates the day/month/year, etc, which
                         #    DateTime itself will do when we pass it the offset.


            my $*USE-ORIGINAL-DATETIME-NEW = True;

            my \tz-aware = callwith(self, posix, :timezone(time.gmt-offset))
                but TimezoneAware[
                    tz-id,         # The Olson ID (e.g. America/New_York)
                    time.tz-abbr,  # The nominal zone (e.g. EST/EDT)
                    time.dst.Bool  # Daylight saving time status.
            ];
            tz-aware.^set_name('DateTime');
            return tz-aware
        }


        # The user instead gave us (in some way) a set of day/month/year/etc.
        # Once we get them, we can use a common processing method.
        use DateTime::Timezones::Classes;
        my Time \time-in = Time.new;

        if c ~~ :(Str $) {
            # parse the format string here and set Time's elements.
            die "Invalid DateTime string '{c.list.head}'; use an ISO 8601 timestamp (yyyy-mm-ddThh:mm:ssZ or yyyy-mm-ddThh:mm:ss+01:00) instead"
                unless c.list.head ~~ /
                    (<[+-]>? \d**4 \d*)                            # 0 year
                    '-'
                    (\d\d)                                         # 1 month
                    '-'
                    (\d\d)                                         # 2 day
                    <[Tt]>                                         # time separator
                    (\d\d)                                         # 3 hour
                    ':'
                    (\d\d)                                         # 4 minute
                    ':'
                    (\d\d[<[\.,]>\d ** 1..12]?)                    # 5 second
                    [<[Zz]> | (<[\-\+]> \d\d) [':'? (\d\d)]? ]?    # 6:7 timezone
            /;
            time-in.year       = +$0;
            time-in.month      = +$1;
            time-in.day        = +$2;
            time-in.hour       = +$3;
            time-in.minute     = +$4;
            time-in.second     =  $5.Numeric.floor.Int;
            time-in.gmt-offset = ($6 // 0) * 3600 + ($7 // 0) * 60;
        } elsif c ~~ :(DateTime $, *%) {
            my \orig = c.list.head;
            my \args = c.hash;
            time-in.year       = args<year>         // orig.year;
            time-in.month      = args<month>        // orig.month;
            time-in.day        = args<day>          // orig.day;
            time-in.hour       = args<hour>         // orig.hour;
            time-in.minute     = args<minute>       // orig.minute;
            time-in.second     = args<second>.floor // orig.second.floor; # may be fractional
            time-in.dst        = args<daylight>     // -1;
            time-in.gmt-offset = args<timezone> ~~ Int ?? args<timezone> !! orig.offset;
        } elsif c ~~ :(Int() $Y, Int() $M, Int()     $D,
                       Int() $h, Int() $m, Numeric() $s) {
            # Positional based explicit formatting
            my \args = c.list;
            time-in.year       = args[0];
            time-in.month      = args[1];
            time-in.day        = args[2];
            time-in.hour       = args[3];
            time-in.minute     = args[4];
            time-in.second     = args[5].floor; # may be fractional
            time-in.dst        = c.hash<daylight> // -1;
            time-in.gmt-offset = c.hash<timezone> ~~ Int ?? c.hash<timezone> !! 0;
        } elsif c ~~ :( :$year, *%) {
            # Named arguments only.  If not present, default value.
            my \args = c.hash;
            time-in.year       =  args<year>               - 1900;
            time-in.month      = (args<month>        // 1) - 1;
            time-in.day        =  args<day>          // 1;
            time-in.hour       =  args<hour>         // 0;
            time-in.minute     =  args<minute>       // 0;
            time-in.second     = (args<second>       // 0).floor.Int; # may be fractional
            time-in.dst        =  args<daylight>     // -1;
            time-in.gmt-offset =  args<timezone> ~~ Int ?? args<timezone> !! 0;
        } else {
            die "Passed bad arguments to DateTime somehow";
        }


        # Now that we have figured out the YMD/hms we need to create
        # we figure out the timezone.

        my \tz-id = c.hash<timezone> ~~ Str ?? c.hash<timezone> !! 'Etc/GMT';
        my \tz = get-timezone-data tz-id;
        my \time = gmt-from-local tz, time-in;
        #if tz-id eq 'Etc/GMT' {
        #    # There's no need to feed this back through into the timezone
        #    my $*USE-ORIGINAL-DATETIME-NEW = True;
        #    my \tz-aware = callwith(self, time)
        #        but TimezoneAware[tz-id,'GMT',False];
        #    tz-aware.^set_name('DateTime');
        #    return tz-aware

        # Now we run it back through localtime, to ensure we have the right
        # offsets and dst settings.
        say "When checking, our time object is ", time;
        my \time-out = localtime tz, time;
            say "Time out is", time-out;
        my $*USE-ORIGINAL-DATETIME-NEW = True;
        my \tz-aware = callwith(self, time)
            but TimezoneAware[tz-id,time-out.tz-abbr,time-out.dst];
        tz-aware.^set_name('DateTime');
        return tz-aware

    }
);

INIT DateTime.^find_method('timezone').wrap(
    method (|c) {
        with self.?olson-id {
            callsame() but self.?olson-id
        }else{
            callsame()
        }
    }
);

INIT DateTime.^find_method('in-timezone').wrap(
    method (|c) {
        if CALLERS::<$*USE-ORIGINAL-DATETIME-NEW> {
            return callwith self, c.list.head
        }

        if c ~~ :($ where Int|Str) {
            # TODO check if string can be made into integer
            return self.new: self.posix, :timezone(c.list.head)
        } else {
            "Bad arguments for in-timezone";
        }
    }
);

INIT DateTime.^find_method('posix').wrap(
    method (|c) {
        if c ~~ :() {
            my int $a = (14 - self.month) div 12;
            my int $y = self.year + 4800 - $a;
            my int $m = self.month + 12 * $a - 3;
            my int $jd = self.day + (153 * $m + 2) div 5 + 365 * $y
                + $y div 4 - $y div 100 + $y div 400 - 32045;
            ($jd - 2440588) * 86400
              + self.hour      * 3600
              + self.minute    * 60
              + self.whole-second
              - self.offset # we add this offset from the original NQP routine
        } else {
            die "No arguments allowed for .posix";
        }
    }
)