unit module Routines;
use DateTime::Timezones::Classes;

sub get-timezone-data($olson-id) is export {
    # Here we load the timezone data based on the Olson ID
    # and return it as a State object;
    state %cache;
    .return with %cache{$olson-id};

    use DateTime::Timezones::State;
    %cache{$olson-id} := State.new:
            %?RESOURCES{"TZif/$olson-id"}.slurp(:bin), :name($olson-id);
}



# used in localtime, see its pod.
sub timesub { ... }

=begin pod

The other routines that need to implemented are those found in localtime:

    struct tm *
    localtime_rz(struct state *sp, time_t const *timep, struct tm *tmp)
    {
      return localsub(sp, timep, 0, tmp);
    }

This requires to implement them standard C<tm> struct (which contains
simple date information as integers) as well as the C<state> struct which
is used while processing (see C<Classes.pm6> for both).  The C<time_t>
constant is actually just a string that identifies the timezone.  In effect,
this would be in Raku

    localtime (State state, str timezone-id, Time time ) {
        localsub state, timezone-id, 0, time
    }

There's a weird (to me) reason why there is this indirection according to
the C code's comments:

    ** The easy way to behave "as if no library function calls" localtime
    ** is to not call it, so we drop its guts into "localsub", which can be
    ** freely called. (And no, the PANS doesn't require the above behavior,
    ** but it *is* desirable.)

Since this has really nothing to do with us, we can just safely implement
the localsub as localtime which is the intended use.  Because this is a
longer routine, I will divide the comments and the original code more
fully.

    localsub(struct state const *sp, time_t const *timep, int_fast32_t setname,
         struct tm *const tmp)
    {

State is a horribly named construct, it's actually the time zone ruleset!

=end pod

use DateTime::Timezones::State;
sub localtime (
        State $state,         #| Timezone information
        int $time,            #| The time to convert (as seconds since epoch)
        int32 $setname,       #| Not used in Raku code
        Time $temp = Time.new #| This may eventually be made later, to keep it inmutable
) is export {

    =begin pod
    The C code then prepares the following variables

        register const struct ttinfo *	ttisp;
        register int			i;
        register struct tm *		result;
        const time_t		t = *timep;

    ttinfo is another structure that we have defined as a class (TimeInfo)
    in Classes.pm6 that describes additional time information not visible
    in the time.

    Note that C<$timezone-id> is immediately stored in t.  Because of how
    Raku subs work, we shall suffice to recall that C's C<t> is Raku's C<$timezone-id>
    =end pod

    my TransitionInfo $ttisp;
    my int $i = 0;
    my Time $result; # Currently immutable


    =begin pod
    The next bit returns GMT if the State object is empty:

        if (sp == NULL) {
          /* Don't bother to set tzname etc.; tzset has already done it.  */
          return gmtsub(gmtptr, timep, 0, tmp);
        }

    This shouldn't happen, because we're going to require a timezone to be placed.
    =end pod

    without $state {
        die "need to finish gmt sub";# TODO create GMT sub
    }

    =begin pod
    Next we begin with the first major if block, for unspecified dates but
    where we can use the 400 year gregorian cycle to predict (protip: rare)

        if ((sp->goback && t < sp->ats[0]) ||
            (sp->goahead && t > sp->ats[sp->timecnt - 1])) {
                time_t			newt = t;
                register time_t		seconds;
                register time_t		years;

                if (t < sp->ats[0])
                    seconds = sp->ats[0] - t;
                else	seconds = t - sp->ats[sp->timecnt - 1];
                --seconds;
                years = (seconds / SECSPERREPEAT + 1) * YEARSPERREPEAT;
                seconds = years * AVGSECSPERYEAR;
                if (t < sp->ats[0])
                    newt += seconds;
                else	newt -= seconds;
                if (newt < sp->ats[0] ||
                    newt > sp->ats[sp->timecnt - 1])
                        return NULL;	/* "cannot happen" */
                result = localsub(sp, &newt, setname, tmp);
                if (result) {
                    register int_fast64_t newy;

                    newy = result->tm_year;
                    if (t < sp->ats[0])
                        newy -= years;
                    else	newy += years;
                    if (! (INT_MIN <= newy && newy <= INT_MAX))
                        return NULL;
                    result->tm_year = newy;
                }
                return result;
        }

    Which should result in the following Raku code:
    =end pod

    # Recall that state.ats is an array of transition times
    if ($state.go-back && $time < $state.ats.head)
    || ($state.go-ahead && $time > $state.ats.tail) {
        my int64 $newtime = $time;
        my int64 $seconds;
        my int64 $years;

        if $time < $state.ats.head {
            $seconds = $state.ats.head - $time;
        } else {
            $seconds = $time - $state.ats.tail;
        }

        $seconds--;

        # 12622780800 = SECONDS-PER-REPEAT (seconds per gregorian cycle)
        # 400 = YEARS-PER-REPEAT (years in a gregorian cycle)
        # 31556952 = AVG-SECONDS-PER-YEAR
        $years = ($seconds / 12622780800 + 1) * 400;
        $seconds = $years * 31556952;

        if $time < $state.ats.head {
            $newtime += $seconds;
        } else {
            $newtime -= $seconds;
        }

        if $newtime < $state.ats.head
        || $newtime > $state.ats.tail {
            return Nil;
            # Per C code, "This cannot happen";
        }

        # Basically, shift us by 400 years and retry
        $result = localtime $state, $newtime, $setname, $temp;

        with $result {
            my int64 $newyear;
            $newyear = $result.year;
            if $time < $state.ats.head {
                $newyear -= $years;
            } else {
                $newyear += $years;
            }
            # The C code inserts here an min/max value check for newyear
            # to see that it's between INT_MIN and INT_MAX.
            # We should only be dealing with valid values so
            # there shouldn't be a problem.  But… maybe?
            $result.year = $newyear;
        }
        return $result;
    }

    =begin pod
    The second major if checks if we need to use the default type.
    In all files compiled post-2018, the default type is 0.
    Otherwise, does a binary search to find the most appropriate
    moment in time.

        if (sp->timecnt == 0 || t < sp->ats[0]) {
            i = sp->defaulttype;
        } else {
            register int	lo = 1;
            register int	hi = sp->timecnt;

            while (lo < hi) {
                register int	mid = (lo + hi) >> 1;

                if (t < sp->ats[mid])
                    hi = mid;
                else	lo = mid + 1;
            }
            i = (int) sp->types[lo - 1];
        }
        ttisp = &sp->ttis[i];
    =end pod

    if ($state.time-count == 0)
            || ($time < $state.ats.head) {
        $i = 0;
        # should be default type; always 0 in post 2018 files
    } else {
        my int16 $hi = $state.time-count;
        my int16 $lo = 1;
        while $lo < $hi {
            my int16 $mid = ($lo + $hi) div 2;
            if $time < $state.ats[$mid] {
                $hi = $mid;
            } else {
                $lo = $mid + 1;
            }
        }
        $i = $state.types[$lo - 1];
    }
    $ttisp = $state.ttis[$i];

    =begin pod
    Thence we run the timesub.  We shouldn't ever get a Nil response
    and we copy in some of the data from the original ttisp (not sure
    why the timesub doesn't do that anyways.  Weird.
    But some of the stuff (updating tzname) is out of the scope of what
    we're using the code for.

            result = timesub(&t, ttisp->tt_utoff, sp, tmp);
            if (result) {
              result->tm_isdst = ttisp->tt_isdst;
            #ifdef TM_ZONE
              result->TM_ZONE = (char *) &sp->chars[ttisp->tt_desigidx];
            #endif /* defined TM_ZONE */
              if (setname)
                update_tzname_etc(sp, ttisp);
            }
            return result;
        }
    =end pod
    $result = timesub($time, $ttisp.utoffset, $state);
    with $result {
        $result.dst = $ttisp.is-dst;
        $result.tz-abbr = $ttisp.abbr;
    }
    $result;
}

sub isleap ($y) {
    ($y mod 4) == 0 && ($y mod 100) != 0 || ($y mod 400) == 0
}

sub leaps_thru_end_of($y) {
    sub leaps_thru_end_of_nonneg ($y) { $y div 4 - $y div 100 + $y div 400}

    $y < 0
            ?? -1 - leaps_thru_end_of_nonneg(-1 - $y)
            !! leaps_thru_end_of_nonneg($y);
}
my int16 @year_lengths = 365, 366;
#my int16 @month_lengths[2;12] = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31),
#                                (31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
my @month_lengths = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31),
                    (31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

# This is where the bulk of the nasty calculations are done
sub timesub (int64 $time, int32 $offset, State $state, Time $tmp = Time.new) is export {
    #`<<<<
    timesub(const time_t *timep, int_fast32_t offset,
	const struct state *sp, struct tm *tmp)
{
	register const struct lsinfo *	lp;
	register time_t			tdays;
	register int			idays;	/* unsigned would be so 2003 */
	register int_fast64_t		rem;
	int				y;
	register const int *		ip;
	register int_fast64_t		corr;
	register bool			hit;
	register int			i;
	>>>>
    my LeapSecondInfo $lp;
    my int64 $tdays = $time div 86400; # SECSPERDAY
    my int64 $idays;
    # why unsigned not even the original authors know.
    my int64 $rem = $time mod 86400;
    # ^^ they quipped unsigned would be "so 2003"
    my int64 $y = 1970;
    # EPOCH_YEAR
    my int16 $ip;
    my int64 $corr = 0;
    # leapsecond correct applied
    my Bool  $hit = False;
    my int16 $i = $state.leap-count;

    #`<<<<
	while (--i >= 0) {
		lp = &sp->lsis[i];
		if (*timep >= lp->ls_trans) {
			corr = lp->ls_corr;
			hit = (*timep == lp->ls_trans
			       && (i == 0 ? 0 : lp[-1].ls_corr) < corr);
			break;
		}
	}

	Calculate the adjustment based on leapseconds.
    >>>>

    while --$i ≥ 0 {

        $lp = $state.lsis[$i];
        if $time ≥ $lp.transition {
            $corr = $lp.correct;
            $hit = ($time == $lp.transition)
                    && ($i == 0 ?? 0 !! ($state.lsis[$i - 1].corr < $corr));
            last;
        }
    }


    #`<<<<
	while (tdays < 0 || tdays >= year_lengths[isleap(y)]) {
		int		newy;
		register time_t	tdelta;
		register int	idelta;
		register int	leapdays;

		tdelta = tdays / DAYSPERLYEAR;
		if (! ((! TYPE_SIGNED(time_t) || INT_MIN <= tdelta)
		       && tdelta <= INT_MAX))
		  goto out_of_range;
		idelta = tdelta;
		if (idelta == 0)
			idelta = (tdays < 0) ? -1 : 1;
		newy = y;
		if (increment_overflow(&newy, idelta))
		  goto out_of_range;
		leapdays = leaps_thru_end_of(newy - 1) -
			leaps_thru_end_of(y - 1);
		tdays -= ((time_t) newy - y) * DAYSPERNYEAR;
		tdays -= leapdays;
		y = newy;
	}>>>>
    while $tdays < 0 || $tdays >= @year_lengths[isleap $y] {
        my int64 $newy = $y;
        my int64 $tdelta;
        my int64 $idelta;
        my int16 $leapdays;

        $idelta = $tdelta = $tdays div 366;
        # DAYSPERLYEAR - note the L
        if $idelta == 0 {
            $idelta = ($tdays < 0) ?? -1 !! 1;
        }

        # C has a increment overflow check here
        # increment_overflow(newy, idelta)
        # I don't think that should happen so for now
        $newy += $idelta;

        $leapdays = leaps_thru_end_of($newy - 1) - leaps_thru_end_of($y - 1);
        $tdays -= ($newy - $y) * 365; # DAYSPERNYEAR
        #say "After year stuff, tdays is $tdays";
        $tdays -= $leapdays;
        #say "After leapdays, tdays is $tdays";
        $y = $newy;
    }
    #`<<<<
	/*
	** Given the range, we can now fearlessly cast...
	*/
	idays = tdays;
	rem += offset - corr;
	while (rem < 0) {
		rem += SECSPERDAY;
		--idays;
	}
	while (rem >= SECSPERDAY) {
		rem -= SECSPERDAY;
		++idays;
	}
	>>>>
    $idays = $tdays;
    $rem += $offset - $corr;
    while $rem < 0 {
        $rem += 86400; # SECSPERDAY;
        $idays--;
    }
    while $rem ≥ 86400 { # SECSPERDAY
        $rem -= 86400;
        $idays++;
    }

    #`<<<<
	while (idays < 0) {
		if (increment_overflow(&y, -1))
		  goto out_of_range;
		idays += year_lengths[isleap(y)];
	}
	while (idays >= year_lengths[isleap(y)]) {
		idays -= year_lengths[isleap(y)];
		if (increment_overflow(&y, 1))
		  goto out_of_range;
	}
	tmp->tm_year = y;
	if (increment_overflow(&tmp->tm_year, -TM_YEAR_BASE))
	  goto out_of_range;
	tmp->tm_yday = idays;
    >>>>

    while $idays < 0 {
        $y += -1; # increment_overflow check;
        $idays += @year_lengths[isleap $y];
    }
    while $idays ≥ @year_lengths[isleap $y] {
        $idays -= @year_lengths[isleap $y];
        $y += 1;
        # increment overflow check
    }

    $tmp.year = +$y;
    $tmp.year += -1900; # TM_YEAR_BASE, increment overflow
    $tmp.yearday = $idays;

    #`<<<<
	/*
	** The "extra" mods below avoid overflow problems.
	*/
	tmp->tm_wday = EPOCH_WDAY +
		((y - EPOCH_YEAR) % DAYSPERWEEK) *
		(DAYSPERNYEAR % DAYSPERWEEK) +
		leaps_thru_end_of(y - 1) -
		leaps_thru_end_of(EPOCH_YEAR - 1) +
		idays;
	tmp->tm_wday %= DAYSPERWEEK;
	if (tmp->tm_wday < 0)
		tmp->tm_wday += DAYSPERWEEK;
    >>>>
    $tmp.weekday = 4 + # EPOCHWDAY
            (($y - 1970) mod 7) * # EPCHO YEAR, DAYSPERWEEK
            (365 mod 7) + # DAYSPERNYEAR, DAYSPERWEEK
            leaps_thru_end_of($y - 1) -
            leaps_thru_end_of(1969) + # EPOCH_YEAR - 1
            $idays;
    $tmp.weekday mod= 7; # DAYSPERWEEK
    if $tmp.weekday < 0 {
        $tmp.weekday += 7; # DAYSPERWEEK
    }

    #`<<<<
	tmp->tm_hour = (int) (rem / SECSPERHOUR);
	rem %= SECSPERHOUR;
	tmp->tm_min = (int) (rem / SECSPERMIN);
	>>>>
    $tmp.hour = $rem div 3600; # SECSPERHOUR
    $rem mod= 3600; # SECSPERHOUR
    $tmp.minute = $rem div 60; #SECSEPERMIN

    #`<<<<
	/*
	** A positive leap second requires a special
	** representation. This uses "... ??:59:60" et seq.
	*/
	tmp->tm_sec = (int) (rem % SECSPERMIN) + hit;
	ip = mon_lengths[isleap(y)];
	for (tmp->tm_mon = 0; idays >= ip[tmp->tm_mon]; ++(tmp->tm_mon))
		idays -= ip[tmp->tm_mon];
	tmp->tm_mday = (int) (idays + 1);
	>>>>
    $tmp.second = $rem mod 60 + $hit;
    # SECSPERMIN
    my int16 @ip = isleap($y)
            ?? (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
            !! (31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
    $tmp.month = 0;

    while $idays ≥ @ip[$tmp.month] {
        $idays -= @ip[$tmp.month++];
    }

    #loop ($tmp.month = 0; $idays ≥ @ip[$tmp.month]; $tmp.month++) {
    #    $idays -= @ip[$tmp.month];
    #}
    $tmp.day = $idays ; #+ 1; WHY PLUS ONE? This seems to cause an off-by-one-day error in Raku

    #`<<<<
	tmp->tm_isdst = 0;
#ifdef TM_GMTOFF
	tmp->TM_GMTOFF = offset;
#endif /* defined TM_GMTOFF */
	return tmp;
	>>>>
    $tmp.dst = 0;
    $tmp.gmt-offset = $offset;

    return $tmp;

    #`<<<<
 out_of_range:
	errno = EOVERFLOW;
	return NULL;
}
>>>>
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
multi sub gmt-from-local (DateTime $t, $timezone, $daylight?) is export  {
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
multi sub gmt-from-local (State $state, Time $time) {

    =begin pod
    Thence it begins setting up some variables that it will use.
        register time_t			t;
        register int			samei, otheri;
        register int			sameind, otherind;
        register int			i;
        register int			nseen;
        char				seen[TZ_MAX_TYPES];
        unsigned char			types[TZ_MAX_TYPES];
        bool				okay;
    Here, the variables are t (a Time object), the rest will described as they
    are reached in the code.
    =end pod

    my int64 $t;
    my int16 $samei;
    my int16 $otheri;
    my int16 $sameind;
    my int16 $i;
    my int16 $nseen;
    my int8  @seen[256] #`(tz-max-types, 256);
    my int8  @types[256] #`(tz-max-types, 256);
    my Bool  $okay = False;

    =begin pod
    This next bit does some error handling that's not necessary in Raku
    and then corrects DST (probably not necessary in Raku since we'll
    be setting DST by other means). Inside of the Time structure, the
    values for DST are thus
    -  1: Daylight savings / Summer time
    -  0: Standard time
    - -1: Unsure/use heuristics

        if (tmp == NULL) {
            errno = EINVAL;
            return WRONG;
        }
        if (tmp->tm_isdst > 1)
            tmp->tm_isdst = 1;
        t = time2(tmp, funcp, sp, offset, &okay);
    After correcting for that, we call the time2 function, which in Raku we're calling
    calculate-gmt-from-local.  Note that the funcp for us is always localsub for the time
    being
    =end pod
    $t = calculate-gmt-from-local($time, $state, 0, $okay); # offset is always 0

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
            $t = calculate-gmt-from-local $time, $state, 0, $okay; # TODO where offset? orig 3 arg methinks it's always zero?
            return $t if $okay;
            $time.second -= ($state.ttis[$otheri].utoffset - $state.ttis[$samei].utoffset);
            $time.dst = $time.dst == 0 ?? 1 !! 0;
        }
    }
    return -11;
    #sdie "Unable to calculate time, very confused";
}


# This actually comes from time2, and called in time1)
=begin pod
The time2 is where the main actual almost (!) occurs.
Because of leapseconds, it could potential be run twice, depending on the results.
It is simply:
    static time_t
    time2(struct tm * const	tmp,
          struct tm *(*funcp)(struct state const *, time_t const *,
                  int_fast32_t, struct tm *),
          struct state const *sp,
          const int_fast32_t offset,
          bool *okayp)
    {
        time_t	t;

        /*
        ** First try without normalization of seconds
        ** (in case tm_sec contains a value associated with a leap second).
        ** If that fails, try with normalization of seconds.
        */
        t = time2sub(tmp, funcp, sp, offset, okayp, false);
        return *okayp ? t : time2sub(tmp, funcp, sp, offset, okayp, true);
    }
=end pod

sub calc-gmt-lcl-sub ($,$,$,$) {
    ...
    }
#| This is time2 in C code
sub calculate-gmt-from-local(
        Time $time,
        #`(funcp is assumed)
        State $state,
        int32 $offset #`(basically always 0) ,
        Bool $okay is rw
) { # offset, which should be the final arg, is always 0
    my int64 $t = calc-gmt-lcl-sub $time, $state, $offset, $okay, False;
    return $t if $okay;
    calc-gmt-lcl-sub $time, $state, $offset, $okay, True;
}

#|This is time2sub in C code
sub calc-gmt-lcl-sub (Time $time, State $state, int32 $offset, $okay is rw, Bool $do-norm-secs) {
    my int16 $dir;
    my int16 $i;
    my int16 $j;
    my int16 $saved-seconds;
    my int32 $li;
    my int64 $lo;
    my int64 $hi;
    my int32 $y;
    my int64 $new-t;
    my int64 $t;
    my Time $your-time;
    my Time $my-time;

    #| Returns true if adding the arguments would result in an overflow error.
    #| If not, adds the second argument to the first and returns false.
    sub increment-overflow($i is rw, $j) {
        constant \int-max = #`(my int64 =)  9223372036854775807;
        constant \int-min = #`(my int64 =) -9223372036854775808;
        True if $i ≥ 0
                ?? $j > int-max - $i
                !! $j < int-min - $i
    }
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
        die "Stack overflow" if normalize-overflow $your-time.minute, $your-time.second, 60;
        # sec-per-min
    }
    die "Stack overflow" if normalize-overflow $your-time.hour, $your-time.minute, 60 #`(min-per-hour);
    die "Stack overflow" if normalize-overflow $your-time.day, $your-time.hour, 24 #`(hours-per-day);
    $y = $your-time.year;# NOTE the C code does a normalize overflow but with 32 bit for the year.
    die "Stack overflow" if normalize-overflow $y, $your-time.month, 12 #`(mons-per-year);

    die "Stack overflow" if increment-overflow $y, 1900 #`(tm-year-base);
    while $your-time.day <= 0 {
        die "Stack overflow" if increment-overflow $y, -1;
        $li = $y + ((1 < $your-time.month) ?? 1 !! 0);
        $your-time.day += @year_lengths[isleap $li];
    }
    while $your-time.day > 366 #`(days-per-l-year) {
        $li = $y + ((1 < $your-time.mon) ?? 1 !! 0);
        die "Stack overflow" if increment-overflow($y, 1);
    }
    loop {
        $i = @month_lengths[isleap $y;$your-time.month];
        last if $your-time.day ≤ $i;
        $your-time.day -= $i;
        if ++$your-time.month ≥ 12 #`(mons-per-year) {
            $your-time.month = 0;
            die "Stack overflow" if increment-overflow($y, 1) #`(i-c-32?);
        }
    }
    die "Stack overflow" if increment-overflow #`(i-c-32?) $y, -1900 #`(neg tm-year-base);
    # die "Stack overflow" if !($int-min ≤ $y ≤ $int-max).  Should always be true??
    $your-time.year = $y;

    if 0 ≤ $your-time.second < 60 { # secs-per-min
        $saved-seconds = 0;
    } elsif $y + 1900 #`(tm-year-base) < 1970 #`(epoch-year) {
        # see C notes for why not set to 0
        die "Stack overflow" if increment-overflow $your-time.second, -59 #`(1 - secs-per-min);
        $saved-seconds = $your-time.second;
        $your-time.second = 59 #`(secs-per-min - 1);
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
        if ! ($my-time = localtime $state, $t, $offset) {
            $dir = $t > 0 ?? 1 !! -1;
        } else {
            $dir = time-cmp $my-time, $your-time; # 1 or -1
        }

        if $dir != 0 {
            if $t == $lo {
                return -1 if $t == 9223372036854775807;
                $t++;
                $lo++;
            } elsif $t == $hi {
                return -1 if $t == -9223372036854775808;
                $t--;
                $hi--;
            }
            return -1 if $lo > $hi;
            if $dir > 0 { $hi = $t } else { $lo = $t };
            next
        }

        # The C code now does a compiler directive check for whether
        # gmtoff exists in the tm struct.  We use that, so we include the code here
        # Yes, this is hideously ugly, but it's what they made for us.

        if ($my-time.gmt-offset != $your-time.gmt-offset)
                && ($your-time.gmt-offset > 0
                        ?? (  -86400 ≤ $your-time.gmt-offset
                                && $my-time.gmt-offset ≤ 2147483647 + $your-time.gmt-offset) # smallest(int32max, longmax)
                        !! (  $your-time.gmt-offset ≤ 86400
                                && -2147483648 + $your-time.gmt-offset ≤ $my-time.gmt-offset)
                ) {
            my int64 $alt-t = $t;
            my int32 $diff = $my-time.gmt-offset - $your-time.gmt-offset;
            if !increment-overflow-time($alt-t, $diff) {
                my Time $alt-time;
                if ($alt-time = localtime $state, $alt-t, $offset)
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
            next if $state.ttis[$i].dst != $your-time.dst; # TODO check Bool vs int
            loop ($j = $state.type-count - 1; $j ≥ 0; $j--) {
                next if $state.ttis[$j].dst == $your-time.dst;
                next unless localtime $state, $new-t, $offset, $my-time;
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
    $t = $new-t;
    $okay = True if localtime $state, $t, $offset;
    return $t;
    #die "Error in confirming search";
}

