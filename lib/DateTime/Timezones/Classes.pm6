unit module Classes;
=begin pod

=head1 Translating the C code

There are basically three elements to handling time zones, and each has
a particular struct-ure in the original C code based on reading in the
files.  We will begin by defining our own classes to mimic the C structures
so that as we port the code we can closely follow the original.  No fancy
Raku-isms here, sadly.

=head2 Timezone rules

The C code defines the timezone rule structure in C<zic.c> thus:

    =begin code
    typedef int_fast64_t	zic_t;

    …

    struct rule {
        const char *	r_filename;
        lineno		r_linenum;
        const char *	r_name;

        zic_t		r_loyear;	/* for example, 1986 */
        zic_t		r_hiyear;	/* for example, 1986 */
        const char *	r_yrtype;
        bool		r_lowasnum;
        bool		r_hiwasnum;

        int		r_month;	/* 0..11 */

        int		r_dycode;	/* see below */
        int		r_dayofmonth;
        int		r_wday;

        zic_t		r_tod;		/* time from midnight */
        bool		r_todisstd;	/* is r_tod standard time? */
        bool		r_todisut;	/* is r_tod UT? */
        bool		r_isdst;	/* is this daylight saving time? */
        zic_t		r_save;		/* offset from standard time */
        const char *	r_abbrvar;	/* variable part of abbreviation */

        bool		r_todo;		/* a rule to do (used in outzone) */
        zic_t		r_temp;		/* used in outzone */
    };

    #define DC_DOM		0	/* 1..31 */	/* unused */
    #define DC_DOWGEQ	1	/* 1..31 */	/* 0..6 (Sun..Sat) */
    #define DC_DOWLEQ	2	/* 1..31 */	/* 0..6 (Sun..Sat) */
    =end code

The first two fields can be omitted, because we won't be using them.
We end up with the following class (the C<zic_t> type is just an alias
for a 64-bit int):
=end pod

#`[
class Rule {
    #= Defines how time changes across the years

    has str   $.name;         # The ruleset that this rule belongs to

    has int64 $.low-year;     #= The first year that the rule is used in.
    has int64 $.high-year;    #= The final year that the rule is used in.
    has str   $.year-type;    #= Indicates the type of year the rule should be used in (rare).
    has Bool  $.low-was-num;  #=
    has Bool  $.high-was-num; #=

    has int   $.month;        #= The month for the rule (zero-indexed).
    has int   $.day-code;     #= The method for determining the rule start (0 => exact day, 1 => weekday on/before, 2 => weekday on or after).
    has int   $.day-of-month; #= The day used for anchoring the start of the rule (per C<.day-code>).
    has int   $.weekday;      #= The weekday used for starting the rule (may be ignored based on C<.day-code>)

    has int64 $.time-of-day;  #= The time at which the rule starts.
    has Bool  $.tod-standard; #= If true, C<.time-of-day> is in standard (not daylight savings) time.
    has Bool  $.tod-ut;       #= If true, C<.time-of-day> is in universal time.
    has Bool  $.is-dst;       #= If true, rule set defines daylight savings time.
    has int64 $.save;         #= The offset from standard time.
    has str   $.abbr-var;     #= The variable portion of an abbreviation (replaces %s in Zone).

    has Bool  $.todo;         #= Used in outzone, may be deletable.
    has int64 $.temp;         #= Used in outzone, may be deletable.
}
]

=begin pod
Νext, we define the zones.  Zones are, as their name suggests, based on
specific geographic areas.  In many cases, two zones might share equivalent
rules most of the time, so this distinction helps avoid extensive repetition.
The C code defines the zone as the following

    =begin code
    struct zone {
        const char *	z_filename;
        lineno		z_linenum;

        const char *	z_name;
        zic_t		z_stdoff;
        char *		z_rule;
        const char *	z_format;
        char		z_format_specifier;

        bool		z_isdst;
        zic_t		z_save;

        struct rule *	z_rules;
        ptrdiff_t	z_nrules;

        struct rule	z_untilrule;
        zic_t		z_untiltime;
    };
    =end code

Which converted into Raku code generates leaves us with the following:
=end pod

#`[
class Zone {
    has str   $.name;             #= The name identifying this zone (Continent/City format)
    has int64 $.std-offset;       #= The offset for standard time from GMT
    has str   $.rule;             #= The name of the rule
    has str   $.format;           #= The format of the rule's abbreviation
    has str   $.format-specifier; #= ?

    has Bool  $.is-dst;           #= Returns true if the zone has daylight savings time.
    has int64 $.save;             #= The amount of time saved in daylight savings time.

    has Rule  @.rules;            #= All of the rules that apply to this zone.
    has       $.nrules;           #= My C fails me, but I think this just tell us how many rules there are (== +@rules)

    has Rule  $.until-rule;       #= ?? The new rule to be used when the zone's until is complete
    has int64 $.until-time;       #= The time up to which the zone's definition is in effect
}
]

=begin pod
The last primary class we need to deal with is a link, which simply associates
one zone's name with another.  This is done normally if a city name changes, but
could be done for any number of other reasons.  The C struct is

    =begin code
    struct link {
        const char *	l_filename;
        lineno		l_linenum;
        const char *	l_from;
        const char *	l_to;
    };
    =end code

Which results in a pretty basic Raku class (and in reality, can be massively optimized
later by creating a hash that points to the resolved zones).
=end pod

class Link {
    has str $.from; #= The older/deprecated/alternate name for the zone.
    has str $.to;   #= The current/resolved name for the zone.
}


=begin pod
The classes below are used in the conversion from GMT to localtime.
The first one is a state object, which is really just a parsed
version of the rules/zones for each named zone (e.g. America/New_York).

    =begin code
    struct state {
        int		leapcnt;
        int		timecnt;
        int		typecnt;
        int		charcnt;
        bool		goback;
        bool		goahead;
        time_t		ats[TZ_MAX_TIMES];
        unsigned char	types[TZ_MAX_TIMES];
        struct ttinfo	ttis[TZ_MAX_TYPES];
        char		chars[BIGGEST(BIGGEST(TZ_MAX_CHARS + 1, sizeof gmt),
                    (2 * (MY_TZNAME_MAX + 1)))];
        struct lsinfo	lsis[TZ_MAX_LEAPS];

        /* The time type to use for early times or if no transitions.
           It is always zero for recent tzdb releases.
           It might be nonzero for data from tzdb 2018e or earlier.  */
        int defaulttype;
    };
    =end code

In Raku, we end up with the following (with default values taken from
the routine zoneinit in localtime.c
=end pod
class State {
    has int  $.leap-count = 0; #= Number of leap seconds (e.g. +@!lsis)
    has int  $.time-count = 0; #= Number of transition moments (e.g. +@!ats)
    has int  $.type-count = 0; #= Number of local time type objects (TimeInfo)
    has int  $.char-count = 0; #= Number of characters of timezone abbreviation strings (e.g. @!chars.join.chars)
    has Bool $.go-back   = False; #= Not sure what this does
    has Bool $.go-ahead  = False; #= Not sure what this does
    #`<<<
    The definition for go-back and go-ahead is  (where sp = self)
        if (sp->timecnt > 1) {
            for (i = 1; i < sp->timecnt; ++i)
                if (typesequiv(sp, sp->types[i], sp->types[0]) &&
                    differ_by_repeat(sp->ats[i], sp->ats[0])) {
                        sp->goback = true;
                        break;
                    }
            for (i = sp->timecnt - 2; i >= 0; --i)
                if (typesequiv(sp, sp->types[sp->timecnt - 1],
                    sp->types[i]) &&
                    differ_by_repeat(sp->ats[sp->timecnt - 1],
                    sp->ats[i])) {
                        sp->goahead = true;
                        break;
            }
        }
    >>>
    has int64 @.ats;        #= Moments when timezone information transitions
    has int   @.types;      #= The associated rule for each of the transition moments (@!ats Z @!types)
    has       @.ttis;       #= The rules for the transition time, indicating seconds of offset (Transition time indicator seconds)
    has str   $.chars = ""; #= Timezone abbreviation strings
    has     @.lsis;         #= Leap seconds (pairs of four-byte values)

    method Bool {
        #
           $!leap-count != 0
        || $!time-count != 0
        || $!type-count != 0
        || $!char-count != 0
        || $!go-back
        || $!go-ahead

    }
}
=begin pod
The uses of this aren't entirely clear at the moment, but as I
continue porting, it should be clear whether we need this.

Similar to the above rules, there are two other mini-rule classes:

    =begin code
    enum r_type {
      JULIAN_DAY,		/* Jn = Julian day */
      DAY_OF_YEAR,		/* n = day of year */
      MONTH_NTH_DAY_OF_WEEK	/* Mm.n.d = month, week, day of week */
    };

    struct rule {
        enum r_type	r_type;		/* type of rule */
        int		r_day;		/* day number of rule */
        int		r_week;		/* week number of rule */
        int		r_mon;		/* month number of rule */
        int_fast32_t	r_time;		/* transition time of rule */
    };
    =end code

The enum can be done as one for us, although it can't hold native ints
(not sure if that's a bug --as of 30 July 2020-- but we'll just eat
the autoboxing for now):
=end pod

enum RuleType ( julian-day => 0, day-of-year => 1, month-nth-day-of-week => 2);

class ConversionRule is export {
  has RuleType $.type;  #= The type of rule
  has int      $.day;   #= Day number of rule
  has int      $.week;  #= week number of rule
  has int      $.month; #= month number of rule
  has int32    $.time;  #= Transition time of rule
}


# This is the struct defined in the 'tm' library:
#
#   The <time.h> header defines the tm structure that contains calendar dates
#   and time broken down into components.  The following standards-compliant
#   fields are present:
#
#           Type    Field      Represents                     Range
#           int     tm_sec     Seconds                        [0, 61]
#           int     tm_min     Minutes                        [0, 59]
#           int     tm_hour    Hours since midnight           [0, 23]
#           int     tm_mday    Day of the month               [1, 31]
#           int     tm_mon     Months since January           [0, 11]
#           int     tm_year    Years since 1900
#           int     tm_wday    Days since Sunday              [0, 6]
#           int     tm_yday    Days since January 1           [0, 365]
#           int     tm_isdt    Positive if daylight savings   >= 0
#
#   […]
#
#   NetBSD Extensions
#   In addition, the following NetBSD-specific fields are available:
#
#           Type             Field      Represents
#           int              tm_gmtoff  Offset from UTC in seconds
#           __aconst char    tm_zone    Timezone abbreviation
#
#   […]
#
#   The tm_gmtoff field denotes the offset (in seconds) of the time
#   represented from UTC, with positive values indicating east of the Prime
#   Meridian.  The tm_zone field will become invalid and point to freed
#   storage if the corresponding struct tm was returned by localtime_rz(3)
#   and the const timezone_t tz argument has been freed by tzfree(3).

class Time is export {
    has int $.second is rw;       #= 0..61 (for leapseconds)
    has int $.minute is rw;       #= 0..59
    has int $.hour is rw;         #= 0..23
    has int $.day is rw;          #= 1..31
    has int $.month is rw;        #= Months since January 0..11
    has int $.year is rw;         #= Years since 1900 (1910 = 10; 1899 = -1)
    has int $.weekday is rw;      #= 0..6 (Sunday = 0)
    has int $.yearday is rw;      #= 0..365 (Day index in year)
    has int $.dst is rw;          #= 1 if daylight savings time, 0 if not, -1 if unknown/automatic
    has int $.gmt-offset is rw;   #= Offset in seconds (positive = east of GMT)
    has str $.tz-abbr is rw = ""; #= Timezone abbreviation NULL AFTER localtime
    multi method gist(::?CLASS:D:) {
        "{$!year+1900}-{$!month+1}-$!day at $!hour:$!minute:$!second, Z{$!gmt-offset < 0 ?? '-' !! '+' }{abs $!gmt-offset}";
    }
}

#struct ttinfo {				/* time type information */
#	int_fast32_t	tt_utoff;	/* UT offset in seconds */
#	bool		tt_isdst;	/* used to set tm_isdst */
#   int		tt_desigidx;	/* abbreviation list index */
#   bool		tt_ttisstd;	/* transition is std time */
#   bool		tt_ttisut;	/* transition is UT */
#};

#| Defines information related to a time element, used internally in calculations
class TransitionInfo is export {
    has int32 $.utoffset   is rw; #= The offset from universal time in seconds
    has Bool  $.is-dst     is rw; #= Whether daylight savings time
    has int   $.abbr-index is rw; #= Index in the list of abbreviations
    has Bool  $.is-std     is rw; #= If true, transition is in standard time, else wall clock)
    has Bool  $.is-ut      is rw; #= If true, transition is in universal time, else local time).
    has str   $.abbr       is rw; #= The actual string abbreviation (not from C)
}

class LeapSecondInfo is export {
    has int64 $.transition; # When the leap second occurs
    has int64 $.correction; # How much time is added / subtracted
    method new(blob8 $b) {
        if $b.elems == 8 {
            return self.bless:
                    :transition($b.read-int32: 0),
                    :cummulative($b.read-int32: 4)
        } elsif $b.elems == 12 {
            return self.bless:
                    :transition($b.read-int64: 0),
                    :cummulative($b.read-int32: 8)
        } else {
            die "Bad leap second information passed";
        }
    }
}