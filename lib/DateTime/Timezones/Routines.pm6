unit module Routines;
use DateTime::Timezones::Classes;

# Utility functions and constants
constant INT-MAX =  9223372036854775807;
constant INT-MIN = -9223372036854775808;
constant INT32MAX =  2147483647;
constant INT32MIN = -2147483648;
constant SECS-PER-MIN  = 60;
constant SECS-PER-DAY = 86400;
constant SECS-PER-HOUR = 3600;
constant SECS-PER-REPEAT = 12622780800;
constant AVG-SECONDS-PER-YEAR = 31556952;
constant MINS-PER-HOUR = 60;
constant HOURS-PER-DAY = 24;
constant DAYS-PER-WEEK = 7;
constant DAYS-PER-L-YEAR = 366;
constant DAYS-PER-N-YEAR = 365;
constant MONS-PER-YEAR = 12;
constant YEARS-PER-REPEAT = 400;
constant TM-YEAR-BASE = 1900;
constant EPOCH-WDAY = 4;
constant EPOCH-YEAR = 1970;
constant TZ-MAX-TYPES = 256;

sub isleap ($y) { ($y mod 4) == 0 && ($y mod 100) != 0 || ($y mod 400) == 0 }
my int32 @year_lengths  = 365, 366;
my       @month_lengths = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31),
                          (31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

sub increment-overflow($i is rw, $j) {
    return True if $i ≥ 0
        ?? $j > INT-MAX - $i
        !! $j < INT-MIN - $i;
    $i += $j;
    return False;
}

sub get-timezone-data($olson-id) is export {
    # Here we load the timezone data based on the Olson ID
    # and return it as a State object;

    state %cache;
    .return with %cache{$olson-id};

    use DateTime::Timezones::State;
    %cache{$olson-id} := State.new:
            %?RESOURCES{"TZif/$olson-id"}.slurp(:bin), :name($olson-id);
}


use DateTime::Timezones::State;
# In effect, for us localtime is the same as localsub
# Since localtime_rz immediately calls localsub(state,t,0,time)
sub localtime (
        State $state,         #| Timezone information
        int $t,               #| The time to convert (as seconds since epoch)
        Time $time = Time.new #| This may eventually be made later, to keep it inmutable
) is export {

    my TransitionInfo $ttisp;
    my int $i = 0;
    my Time $result; # Currently immutable

    # Recall that state.ats is an array of transition times
    if ($state.go-back  && $t < $state.ats.head)
    || ($state.go-ahead && $t > $state.ats.tail) {
        my int64 $new-t = $time;
        my int64 $seconds;
        my int64 $years;

        if $t < $state.ats.head {
            $seconds = $state.ats.head - $t;
        } else {
            $seconds = $t - $state.ats.tail;
        }

        $seconds--;

        $years = ($seconds / SECS-PER-REPEAT + 1) * YEARS-PER-REPEAT;
        $seconds = $years * AVG-SECONDS-PER-YEAR;

        if $t < $state.ats.head {
            $new-t += $seconds;
        } else {
            $new-t -= $seconds;
        }

        if $new-t < $state.ats.head
        || $new-t > $state.ats.tail {
            return Nil; # Per C code, "This cannot happen";
        }

        # Basically, shift us by 400 years and retry
        $result = localtime $state, $new-t, $time;

        with $result {
            my int64 $new-year;

            $new-year = $result.year;
            if $t < $state.ats.head {
                $new-year -= $years;
            } else {
                $new-year += $years;
            }
            # The C code inserts here an min/max value check for newyear
            # to see that it's between INT_MIN and INT_MAX.
            # We should only be dealing with valid values so
            # there shouldn't be a problem.  But… maybe?
            $result.year = $new-year;
        }
        return $result;
    }

    if $state.time-count == 0 || $t < $state.ats.head {
        $i = 0; # should be default type; always 0 in post 2018 files
    } else {
        my int32 $lo = 1;
        my int32 $hi = $state.time-count;
        while $lo < $hi {
            my int32 $mid = ($lo + $hi) div 2;
            if $t < $state.ats[$mid] {
                $hi = $mid;
            } else {
                $lo = $mid + 1;
            }
        }
        $i = $state.types[$lo - 1];
    }
    $ttisp = $state.ttis[$i];

    $result = timesub($t, $ttisp.utoffset, $state);

    with $result {
        $result.dst = $ttisp.is-dst;
        $result.tz-abbr = $ttisp.abbr;
    }

    $result;
}


sub leaps_thru_end_of($y) {
    sub leaps_thru_end_of_nonneg ($y) { $y div 4 - $y div 100 + $y div 400}

    $y < 0
            ?? -1 - leaps_thru_end_of_nonneg(-1 - $y)
            !! leaps_thru_end_of_nonneg($y);
}

# This is where the bulk of the nasty calculations are done
sub timesub (int64 $t, int32 $offset, State $state, Time $tm = Time.new) is export {

    my LeapSecondInfo $lp;
    my int64 $tdays;
    my int32 $idays; # why unsigned not even the original authors know.
    my int64 $rem; # ^^ they quipped unsigned would be "so 2003"
    my int64 $y;
    my int16 $ip;
    my int64 $corr = 0; # leapsecond correct applied
    my Bool  $hit = False;
    my int32 $i;

    $corr = 0;
    $hit = False;
    $i = $state.leap-count;

    while --$i ≥ 0 {
        $lp = $state.lsis[$i];
        if $t ≥ $lp.transition {
            $corr = $lp.correction;
            $hit = ($t == $lp.transition)
                    && ($i == 0 ?? 0 !! ($state.lsis[$i - 1].corr < $corr));
            last;
        }
    }


    $y     =        EPOCH-YEAR;
    $tdays = $t div SECS-PER-DAY;
    $rem   = $t mod SECS-PER-DAY;

    while $tdays < 0 || $tdays ≥ @year_lengths[isleap $y] {
        my int64 $new-y;
        my int64 $tdelta;
        my int64 $idelta;
        my int32 $leapdays;

        $tdelta = $tdays div DAYS-PER-L-YEAR;
        # C has some range check here
        $idelta = $tdelta;
        if $idelta == 0 {
            $idelta = ($tdays < 0) ?? -1 !! 1;
        }


        $new-y = $y;

        # C has a increment overflow check here
        # increment_overflow(newy, idelta)
        # I don't think that should happen so for now
        die "overflow" if increment-overflow $new-y, $idelta;

        $leapdays = leaps_thru_end_of($new-y - 1) - leaps_thru_end_of($y - 1);
        $tdays -= ($new-y - $y) * DAYS-PER-N-YEAR;
        $tdays -= $leapdays;
        $y = $new-y;

    }
    $idays = $tdays;
    $rem += $offset - $corr;
    while $rem < 0 {
        $rem += SECS-PER-DAY;
        $idays--;
    }
    while $rem ≥ SECS-PER-DAY {
        $rem -= SECS-PER-DAY;
        $idays++;
    }

    while $idays < 0 {
        increment-overflow $y, -1; # increment_overflow check;
        $idays += @year_lengths[isleap $y];
    }
    while $idays ≥ @year_lengths[isleap $y] {
        $idays -= @year_lengths[isleap $y];
        increment-overflow $y, 1;
        # increment overflow check
    }

    $tm.year = +$y;
    increment-overflow $tm.year, -TM-YEAR-BASE;
    $tm.yearday = $idays;

    $tm.weekday = EPOCH-WDAY +
            (($y - EPOCH-YEAR) mod DAYS-PER-WEEK) *
            (DAYS-PER-N-YEAR mod DAYS-PER-WEEK) +
            leaps_thru_end_of($y - 1) -
            leaps_thru_end_of(EPOCH-YEAR - 1) +
            $idays;
    $tm.weekday mod= DAYS-PER-WEEK; # DAYSPERWEEK
    if $tm.weekday < 0 {
        $tm.weekday += DAYS-PER-WEEK; # DAYS-PER-WEEK
    }

    $tm.hour = $rem div SECS-PER-HOUR; # SECSPERHOUR
    $rem mod= SECS-PER-HOUR; # SECSPERHOUR
    $tm.minute = $rem div SECS-PER-MIN; #SECSEPERMIN

    $tm.second = $rem mod SECS-PER-MIN + $hit; # SECSPERMIN

    $tm.month = 0;
    while $idays ≥ @month_lengths[isleap $y][$tm.month] {
        $idays -= @month_lengths[isleap $y][$tm.month];
        $tm.month++;
    }

    $tm.day = $idays + 1 ;

    $tm.dst = 0;
    $tm.gmt-offset = $offset;

    return $tm;
}






# To get the GMT from a localtime, we use a different process
# this effectively implements mktime_tzname-->time1 with localsub (localtime in Raku),
# where we have already created an SP object (clled State in Raku)
# and we won't allow a null call like the original
=begin pod
The original signature is the following:
    time1(struct tm *const tmp,
          struct tm *(*funcp) (struct state const *, time_t const *,
                   int_fast32_t, struct tm *),
          struct state const *sp,
          const int_fast32_t offset)
    {
Where tmp is the time we are calling, sp is the timezone information
the offset (from mktime_tzname) is 0, and
=end pod

sub calculate-gmt-from-local { ... }
multi sub gmt-from-local (DateTime $t, $timezone, $daylight? --> Int) is export  {
    my $time = Time.new:
        day => $t.day,
        month => $t.month - 1,
        year => $t.year - 1900,
        hour => $t.hour,
        minute => $t.minute,
        second => $t.second.floor,
        dst => +($daylight // -1);

    my $tz = get-timezone-data $timezone;
    return gmt-from-local $tz, $time;
}


#| Called time1 in the C code.
multi sub gmt-from-local (State $state, Time $time --> Int) {

    my int64 $t;
    my int32 $samei; my int32 $otheri;
    my int32 $sameind; my int32 $otherind;
    my int32 $i;
    my int32 $nseen;
    my int8  @seen[TZ-MAX-TYPES] #`(tz-max-types, 256);
    my int8  @types[TZ-MAX-TYPES] #`(tz-max-types, 256);
    my Bool  $okay = False;

    $t = calculate-gmt-from-local($time, $state, 0, $okay); # offset should generally always be 0

    return $t if $okay;



    $time.dst = 0 if $time.dst < 0;
    if $time.dst < 0 {
        #`(ifdef PCTS #POSIX conformance test suite)
        #`($time.is-dst = 0;)
        #`(else)
        return $t;
        #`(endif)
    }

    # If we arrive here, someone did something bad, and so
    # the C code attempts to try to figure out what they wanted

    @seen[$_] = 0 for ^$state.time-count;
    $nseen = 0;
    for ^$state.time-count -> $i {
        if @seen[$state.types[$i]] == 0 {
            @seen[$state.types[$i]] = 1;
            @types[$nseen++] = $state.types[$i];
        }
    }
    for ^$nseen -> $sameind {
        $samei = @types[$sameind];
        next if $state.ttis[$sameind].is-dst ≠ $time.dst;
        for ^$nseen -> $otherind {
            $otheri = @types[$otherind];
            next if $state.ttis[$otheri].is-dst == $time.dst;
            $time.second += ($state.ttis[$otheri].utoffset - $state.ttis[$samei].utoffset);
            $time.dst = $time.dst == 0 ?? 1 !! 0;  # negation in C
            $t = calculate-gmt-from-local $time, $state, $time.gmt-offset, $okay; # TODO where offset? orig 3 arg methinks it's always zero?
            return $t if $okay;
            $time.second -= ($state.ttis[$otheri].utoffset - $state.ttis[$samei].utoffset);
            $time.dst = $time.dst == 0 ?? 1 !! 0;
        }
    }
    return -11;
    #sdie "Unable to calculate time, very confused";
}



sub calc-gmt-lcl-sub { ... }
#| This is time2 in C code
# This actually comes from time2, and called in time1)
sub calculate-gmt-from-local(
        Time $time,
        #`(funcp is assumed)
        State $state,
        int32 $offset #`(basically always 0) ,
        Bool $okay is rw
) { # offset, which should be the final arg, is always 0
    my int64 $t;

    $t = calc-gmt-lcl-sub $time, $state, $offset, $okay, False;
    return $t if $okay;
    calc-gmt-lcl-sub $time, $state, $offset, $okay, True;
}

#|This is time2sub in C code
sub calc-gmt-lcl-sub (Time $time, State $state, int32 $offset, $okay is rw, Bool $do-norm-secs) {

    my int32 $dir;
    my int32 $i;
    my int32 $j;
    my int32 $saved-seconds;
    my int32 $li;
    my int64 $lo;
    my int64 $hi;
    my int32 $y;
    my int64 $new-t;
    my int64 $t;
    my Time $your-time; my Time $my-time;

    sub increment-overflow-time($i is rw, $j) {
        return True unless $j < 0
                ?? #`(type_signed(time_t) # we use int64 so always true)
                #`(??) -9223372036854775808 #`(int64min) - $j ≤ $i
                #`(!! -1 - $j < $i)
                !! $i ≤ 9223372036854775807 #`(int64max) - $j;
        $i += $j;
        return False
    }
    sub normalize-overflow($tens is rw, $units is rw, $base) {
        my int64 $tens-Δ = $units > 0
                ?? $units div $base
                !! -1 - (-1 - $units) div $base;
        $units -= $tens-Δ * $base;
        increment-overflow $tens, $tens-Δ;
    }
    sub time-cmp(Time \a, Time \b) {
        if    a.year   != b.year   { return a.year   < b.year   ?? -1 !! 1 }
        elsif a.month  != b.month  { return a.month  < b.month  ?? -1 !! 1 }
        elsif a.day    != b.day    { return a.day    < b.day    ?? -1 !! 1 }
        elsif a.hour   != b.hour   { return a.hour   < b.hour   ?? -1 !! 1 }
        elsif a.minute != b.minute { return a.minute < b.minute ?? -1 !! 1 }
        elsif a.second != b.second { return a.second < b.second ?? -1 !! 1 }
        else { return 0 }
    }

    $okay = False;

    # All of these dies could be said to be something like a time exception for
    # an unrepresentable period of time
    $your-time := $time; # or clone? I don't think so
    if $do-norm-secs {
        die "Stack overflow" if normalize-overflow $your-time.minute, $your-time.second, SECS-PER-MIN;
    }
    die "Stack overflow" if normalize-overflow $your-time.hour, $your-time.minute, MINS-PER-HOUR;
    die "Stack overflow" if normalize-overflow $your-time.day, $your-time.hour, HOURS-PER-DAY;
    $y = $your-time.year;# NOTE the C code does a normalize overflow but with 32 bit for the year.
    die "Stack overflow" if normalize-overflow $y, $your-time.month, MONS-PER-YEAR;

    # Y is now an actual year number.  Offset again later
    die "Stack overflow" if increment-overflow $y, TM-YEAR-BASE;
    while $your-time.day <= 0 {
        die "Stack overflow" if increment-overflow $y, -1;
        $li = $y + ((1 < $your-time.month) ?? 1 !! 0);
        $your-time.day += @year_lengths[isleap $li];
    }

    while $your-time.day > DAYS-PER-L-YEAR {
        $li = $y + ((1 < $your-time.mon) ?? 1 !! 0);
        $your-time.day -= @year_lengths[isleap $li];
        die "Stack overflow" if increment-overflow($y, 1);
    }
    loop {
        $i = @month_lengths[isleap $y][$your-time.month];
        last if $your-time.day ≤ $i;
        $your-time.day -= $i;
        if ++$your-time.month ≥ MONS-PER-YEAR {
            $your-time.month = 0;
            die "Stack overflow" if increment-overflow($y, 1);
        }
    }
    die "Stack overflow" if increment-overflow $y, - TM-YEAR-BASE;
    # die "Stack overflow" if !($int-min ≤ $y ≤ $int-max).  Should always be true??
    $your-time.year = $y;

    if 0 ≤ $your-time.second < SECS-PER-MIN {
        $saved-seconds = 0;
    } elsif $y + TM-YEAR-BASE < EPOCH-YEAR {
        # see C notes for why not set to 0
        die "Stack overflow" if increment-overflow $your-time.second, 1 - SECS-PER-MIN;
        $saved-seconds = $your-time.second;
        $your-time.second = SECS-PER-MIN - 1;
    } else {
        $saved-seconds = $your-time.second;
        $your-time.second = 0;
    }


    # Now we do a binary search "regradless time_t type"
    $lo = -9223372036854775808 #`(int64 min);
    $hi =  9223372036854775807 #`(int64 max);

    SEARCH:
    loop {
        $t = ($lo div 2) + ($hi div 2);
        if $t < $lo { #I'm fairly certain this condition can never be met.
            $t = $lo;
        } elsif $t > $hi {
            $t = $hi
        }

        if ! ($my-time = localtime $state, $t) {
            $dir = $t > 0 ?? 1 !! -1;
        } else {
            $dir = time-cmp $my-time, $your-time; # 1 or -1
        }

        # No match,
        if $dir != 0 {
            if $t == $lo {
                return -1 if $t == INT-MAX;
                $t++;
                $lo++;
            } elsif $t == $hi {
                return -1 if $t == INT-MIN;
                $t--;
                $hi--;
            }
            return -1 if $lo > $hi; # probably should die
            if $dir == 1 { $hi = $t } else { $lo = $t };
            next
        }

        # The C code now does a compiler directive check for whether
        # gmtoff exists in the tm struct.  We use that, so we include the code here
        # Yes, this is hideously ugly, but it's what they made for us.

        if ($my-time.gmt-offset != $your-time.gmt-offset)
                && ($your-time.gmt-offset > 0
                        ?? (  (- SECS-PER-DAY) ≤ $your-time.gmt-offset
                                && $my-time.gmt-offset ≤ INT32MAX + $your-time.gmt-offset) # smallest(int32max, longmax)
                        !! (  $your-time.gmt-offset ≤ SECS-PER-DAY
                                && INT32MIN + $your-time.gmt-offset ≤ $my-time.gmt-offset)
                ) {

            my int64 $alt-t = $t;
            my int32 $diff = $my-time.gmt-offset - $your-time.gmt-offset;
            unless increment-overflow-time($alt-t, $diff) {
                my Time $alt-time;
                if ($alt-time = localtime $state, $alt-t)
                        && $alt-time.dst == $my-time.dst
                        && $alt-time.gmt-offset == $your-time.gmt-offset
                        && time-cmp($alt-time, $your-time) == 0 {
                    $t = $alt-t;
                    $my-time = $alt-time;
                }
            }
        }
        last if $your-time.dst < 0 || $my-time.dst == $your-time.dst;
        # return Error if State undefined, never the case for us

        loop ($i = $state.type-count - 1; $i ≥ 0; $i--) {
            next if ($state.ttis[$i].dst??1!!0) != $your-time.dst; # TODO check Bool vs int
            loop ($j = $state.type-count - 1; $j ≥ 0; $j--) {
                next if $state.ttis[$j].dst == $your-time.dst;
                next unless $my-time = localtime $state, $new-t;
                next if time-cmp($my-time, $your-time ≠ 0);
                next if $my-time.dst ≠ $your-time.dst;
                # we have a match!
                $t = $new-t;
                last SEARCH;
            }
        }
        die "Search function turned up no results";
    }
    $new-t = $t + $saved-seconds;
    die "Error in search function" if ($new-t < $t) ≠ ($saved-seconds < 0);
    $t = $new-t;# - $my-time.gmt-offset; # I don't know why the C code doesn't have this, but raku needs the + offset
    $okay = True if localtime $state, $t;
    return $t;
    #die "Error in confirming search";
}

