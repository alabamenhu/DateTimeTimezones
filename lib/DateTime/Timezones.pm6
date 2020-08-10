unit module Timezones;


role TimezoneAware[$olson = "Etc/GMT", $abbr = "GMT", $dst = False] {
    method olson-id   (-->  Str) { $olson }
    method tz-abbr (-->  Str) { $abbr  }
    method is-dst  (--> Bool) { $dst   }
}
subset NotTimezoneAware of DateTime where * !~~ TimezoneAware;

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
                      ?? arg.to-posix.head.floor
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

            time-in.year       = args<year>          // orig.year;
            time-in.month      = args<month>         // orig.month;
            time-in.day        = args<day>           // orig.day;
            time-in.hour       = args<hour>          // orig.hour;
            time-in.minute     = args<minute>        // orig.minute;
            time-in.second     = args<second> ?? args<second>.floor !! orig.second.floor;
            time-in.dst        = args<daylight>      // -1;
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

        my \time-out = localtime tz, time;

        my $*USE-ORIGINAL-DATETIME-NEW = True;
        my \tz-aware = callwith(self, time)
            but TimezoneAware[tz-id,time-out.tz-abbr,time-out.dst.Bool];
        tz-aware.^set_name('DateTime');
        return tz-aware

    }
);

# If we have a writable container and someone calls timezone, we
# should attempt to upgrade to being TimezoneAware.  Otherwise,
# we have to convert on each call.  Because we'll rely on multis,
# the wrapper has to be declared separately, but INIT scoping keeps
# us from polluting.  Only problem is that if we error, our
# message will refer to the *sub* timezone, potentially confusing.
INIT {
    proto sub timezone (|) { * }
    multi sub timezone (TimezoneAware $self, |c) is default {
        IntStr.new: $self.offset, $self.olson-id
    }
    multi sub timezone (NotTimezoneAware $self is rw, |c) {
        $self = DateTime.new: $self;
        IntStr.new: $self.offset, $self.olson-id
    }
    multi sub timezone (NotTimezoneAware $self, |c) {
        DateTime.new($self).timezone
    }

    DateTime.^find_method('timezone').wrap: &timezone
}

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
);

# The TimezoneAware methods require fallback support.
# Because they must be multi'd (depending on the writability of their container)
# we first define each of them as multi subs.
#
# To add as a fallback, the syntax is a bit trickier, wherein we create two
# blocks, one that checks if the method name matches us (always True), and the
# second that returns the actual method (sub, in our case) to be used.

INIT {
    proto sub olson-id (|) { * }
    multi sub olson-id (DateTime $self is rw, |c) {
        $self = DateTime.new: $self;
        $self.olson-id
    }
    multi sub olson-id (DateTime $self, |c) {
        DateTime.new($self).olson-id
    }

    proto sub tz-abbr (|) { * }
    multi sub tz-abbr (DateTime $self is rw, |c) {
        $self = DateTime.new: $self;
        $self.tz-abbr
    }
    multi sub tz-abbr (DateTime $self, |c) {
        DateTime.new($self).tz-abbr
    }

    proto sub is-dst (|) { * }
    multi sub is-dst (DateTime $self is rw, |c) {
        $self = DateTime.new: $self;
        $self.is-dst
    }
    multi sub is-dst (DateTime $self, |c) {
        DateTime.new($self).is-dst
    }


    DateTime.^add_fallback:
        anon sub condition ($object, $want) { $want eq 'olson-id' },
        anon sub calculate ($object, $want) {          &olson-id  };
    DateTime.^add_fallback:
        anon sub condition ($object, $want) { $want eq 'tz-abbr' },
        anon sub calculate ($object, $want) {          &tz-abbr  };
    DateTime.^add_fallback:
        anon sub condition ($object, $want) { $want eq 'is-dst' },
        anon sub calculate ($object, $want) {          &is-dst  };
}