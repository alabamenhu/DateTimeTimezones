#| A module to enable time zones in Raku
unit module Timezones;
use Timezones::ZoneInfo;

# Thanks to lizmat++ for this cool way to extend built-ins
class DateTime is DateTime is export {
    has Str  $.olson-id; #= The unique tag that identifies the timezone
    has Str  $.tz-abbr;  #= A mostly unique abbreviation for the time zone that aligns more closely to popular usage
    has Bool $.is-dst;   #= Whether it is daylight savings time

    #| Creates a new timezone-aware DateTime object
    method new(|c (*@, :$olson-id, :$timezone, *%)) {

        # The logic here is slightly complicated:
        #   with tz-id or timezone and will get-time-data for the gmt offset.
        #   with an offset only
        #      if a clean multiple of 3600: use GMT±X, where X is offset / 3600.
        #      if not, use 'Etc/Unknown' *which requires special handling*
        # todo: if the timezone has an offset, it should be made an Etc/GMT+1 or similar timezone

        my $tz-id;   #= The Olson ID, but different name to avoid clash
        my $tz-data; #= The data structure from the TZ database
        my $gmt-off; #= Our ultimate offset from GMT

        # Determine the Olson ID
        with $timezone {
            when Str     { $tz-id = ~$timezone }
            when Numeric {
                if $timezone %% 3600 {
                    $gmt-off = $timezone;
                    $tz-id = $timezone == 0
                               ?? 'Etc/GMT'
                               !! 'Etc/GMT'
                                 ~ ($timezone ≥ 0 ?? '' !! '+') # neg added by Str.Int conversion
                                 ~ ($timezone / -3600);
                } else {
                    $tz-id = 'Etc/Unknown'
                }
            }
        } else {
            with $olson-id { $tz-id = $olson-id }
            else           { $tz-id = 'Etc/GMT' }
        }

        # If we have an Etc/Unknown, we just pass through
        if $tz-id eq 'Etc/Unknown' {
            # In this case, we just pass through the data, we can't really do much
            my \core-dt = CORE::DateTime.new( |c);
            return self.bless:
                year     => core-dt.year,
                month    => core-dt.month,
                day      => core-dt.day,
                hour     => core-dt.hour,
                minute   => core-dt.minute,
                second   => core-dt.second,
                timezone => core-dt.timezone,
                olson-id => 'Etc/Unknown',
                tz-abbr  => '???',
                is-dst   => False,
        }

        # If we were given a timestamp, let the algorithm figure out our dates
        if c ~~ :(Instant:D, *%)
        || c ~~ :(Numeric:D, *%) {
            my \posix = c.list.head ~~ Instant
                ?? c.list.head.to-posix.head.floor # TODO: deal with the leapsecond here
                !! c.list.head.floor;
            my \tz      = timezone-data $tz-id;
            my \time    = calendar-from-posix posix, tz;
            return self.bless:
                year     =>  time.year + 1900,
                month    =>  time.month + 1,
                day      =>  time.day,
                hour     =>  time.hour,
                minute   =>  time.minute,
                second   =>  time.second,
                is-dst   => (time.dst == 1),
                tz-abbr  =>  time.tz-abbr,
                olson-id =>  $tz-id,
                timezone =>  IntStr.new(time.gmt-offset, $tz-id);
        }

        # If we were given a calendar, figure out the offset, and double check
        # that the offset is correct.  Create a TM object to pass along
        use Timezones::ZoneInfo::Time;

        # we were given a calendar
        my \tm = Time.new;
        # set up the date, for which there are three formats:
        #   1. Positional Date + named HMS
        #   2. Positional ymdHMS
        #   3. Named ymdHMS
        #   String format version not yet supported
        if c ~~ :(Date:D, *%) {
            with c.list[0] {
                tm.year   = .year - 1900;
                tm.month  = .month - 1;
                tm.day    = .day;
            }
            tm.hour   = c.hash<hour>   // 0;
            tm.minute = c.hash<second> // 0;
            tm.second = c.hash<second> // 0;
        } elsif c ~~ :(Int:D $, Int:D $?, Int:D $?, Int:D $?, Int:D $?, $?, *%) {
            tm.year   = c.list[0] // 0;
            tm.month  = c.list[1] // 1;
            tm.day    = c.list[2] // 1;
            tm.hour   = c.list[3] // 0;
            tm.minute = c.list[4] // 0;
            tm.second = c.list[5] // 0;
        } elsif c ~~ :(:$year!, *%) {
            tm.hour   = c.hash<year>;
            tm.minute = c.hash<month>  // 1;
            tm.second = c.hash<day>    // 1;
            tm.hour   = c.hash<hour>   // 0;
            tm.minute = c.hash<second> // 0;
            tm.second = c.hash<second> // 0;
        }
        tm.dst        = c.hash<is-dst>     // -1; # -1 means "we don't know"
        tm.gmt-offset = c.hash<gmt-offset> //  0;

        my \tz      = timezone-data $tz-id;
        my \posix   = posix-from-calendar(tm, tz);
        my \time    = calendar-from-posix posix, tz; # needed basically for those ambiguous times during fallback


        self.bless:
            year     =>  time.year,
            month    =>  time.year,
            day      =>  time.day,
            hour     =>  time.hour,
            minute   =>  time.minute,
            second   =>  time.second,
            is-dst   => (time.dst == 1),
            tz-abbr  =>  time.tz-abbr,
            olson-id =>  $tz-id,
            timezone =>  IntStr.new(time.gmt-offset, $tz-id);
    }
}

# Subsets that may or may not be useful for others
subset NotTimezoneAware of CORE::DateTime where * =:= CORE::DateTime;
subset    TimezoneAware of CORE::DateTime where * ~~  DateTime;

# If we have a writable container and someone calls timezone, we
# should attempt to upgrade to being TimezoneAware.  Otherwise,
# we have to convert on each call.  Because we'll rely on multis,
# the wrapper has to be declared separately, but INIT scoping keeps
# us from polluting.  Only problem is that if we error, our
# message will refer to the *sub* timezone, potentially confusing.
INIT once {
    proto sub timezone (|) { * }
    multi sub timezone (CORE::DateTime $self is rw, :$CORE, |c) {
        return callsame if $CORE;

        $self = DateTime.new: $self;
        IntStr.new: $self.offset, $self.olson-id
    }
    multi sub timezone (CORE::DateTime $self, :$CORE, |c) {
        return callsame if $CORE;

        DateTime.new($self.Instant, timezone => callsame).timezone
    }

    CORE::DateTime.^find_method('timezone').wrap: &timezone
}

INIT once DateTime.^find_method('in-timezone').wrap(
    method (|c) {
        if c ~~ :($ where Int | Str) {
            # TODO check if string can be made into integer
            return DateTime.new: self.Instant, :timezone(c.list.head)
        } else {
            "Bad arguments for in-timezone";
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

INIT once {
    proto sub olson-id (|) { * }
    multi sub olson-id (CORE::DateTime $self is rw, |c) {
        $self = DateTime.new: $self.Instant, timezone => $self.offset;
        $self.olson-id
    }
    multi sub olson-id (CORE::DateTime $self, |c) {
        DateTime.new($self.Instant, timezone => $self.offset).olson-id
    }

    proto sub tz-abbr (|) { * }
    multi sub tz-abbr (CORE::DateTime $self is rw, |c) {
        $self = DateTime.new: $self.Instant, timezone => $self.offset;
        $self.tz-abbr
    }
    multi sub tz-abbr (CORE::DateTime $self, |c) {
        DateTime.new($self.Instant, timezone => $self.offset).tz-abbr
    }

    proto sub is-dst (|) { * }
    multi sub is-dst (CORE::DateTime $self is rw, |c) {
        $self = DateTime.new: $self.Instant, timezone => $self.offset;
        $self.is-dst
    }
    multi sub is-dst (CORE::DateTime $self, |c) {
        DateTime.new($self.Instant, timezone => $self.offset).is-dst
    }


    CORE::DateTime.^add_fallback:
        anon sub condition ($object, $want) { $want eq 'olson-id' },
        anon sub calculate ($object, $want) {          &olson-id  };
    CORE::DateTime.^add_fallback:
        anon sub condition ($object, $want) { $want eq 'tz-abbr' },
        anon sub calculate ($object, $want) {          &tz-abbr  };
    CORE::DateTime.^add_fallback:
        anon sub condition ($object, $want) { $want eq 'is-dst' },
        anon sub calculate ($object, $want) {          &is-dst  };
}