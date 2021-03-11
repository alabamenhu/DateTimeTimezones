
#| The information on timezone and leapseconds for a timezone
unit class State;
use DateTime::Timezones::Classes;

has int16 $.leap-count = 0;     #= Number of leap seconds (e.g. +@!lsis)
has int16 $.time-count = 0;     #= Number of transition moments (e.g. +@!ats)
has int16 $.type-count = 0;     #= Number of local time type objects (TimeInfo)
has int16 $.char-count = 0;     #= Number of characters of timezone abbreviation strings (e.g. @!chars.join.chars)
has Bool  $.go-back    = False; #= Whether the time zone's rules loop in the future.
has Bool  $.go-ahead   = False; #= Whether the time zone's rules loop in the past.
has str   $.chars      = "";    #= Time zone abbreviation strings (null delimited)
has int64 @.ats;                #= Moments when timezone information transitions
has int16 @.types;              #= The associated rule for each of the transition moments (to enable @!ats Z @!types)
has TransitionInfo @.ttis;      #= The rules for the transition time, indicating seconds of offset (Transition time information structure)
has LeapSecondInfo @.lsis;      #= The leap seconds for this timezone.
has str $.name;

multi method gist (::?CLASS:D:) { "TZif:$.name"}
multi method gist (::?CLASS:U:) { "(TZif)" }
#| Creates a new TZ State object from a tzfile blob.
method new (blob8 $tz, :$name) {
    my $VERSION;

    # Check initial header to determine version
    #                 Header:     T    Z    i    f  [v.#][0 xx 15]
    $VERSION = 1 if $tz[^20] ~~ [0x54,0x5A,0x69,0x66,   0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
    $VERSION = 2 if $tz[^20] ~~ [0x54,0x5A,0x69,0x66,0x32,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];

    die "TZ file for $name does not begin with correct header (must begin with 'TZif'),\nBegan with ", $tz[^20]
        unless $VERSION;

    my $pos;

    # Determine the initial position for parsing.
    if $VERSION == 1 {
        # Version 1 files begin immediately after the header.
        $pos = 20
    } else {
        # Version 2 files include a version 1 file for backwards
        # compatibility, but then have a second copy with larger
        # integer sizes, so we scan the file to find that header.
        for 1..^$tz.elems -> $i {
            next unless $tz[$i    ] == 0x54  # T
                     && $tz[$i + 1] == 0x5A  # Z
                     && $tz[$i + 2] == 0x69  # i
                     && $tz[$i + 3] == 0x66  # f
                     && $tz[$i + 4] == 0x32; # 2
            $pos = $i + 20;
            last;
        }
    }

    # First the file contains the counts for different items
    # so we know how long to read each type for.
    # (AFAICT, $ttisgmtcnt == $ttisstdcnt == $typecnt)
    my $ttisgmtcnt = $tz.read-int32: $pos     , BigEndian;
    my $ttisstdcnt = $tz.read-int32: $pos +  4, BigEndian;
    my $leapcnt    = $tz.read-int32: $pos +  8, BigEndian;
    my $timecnt    = $tz.read-int32: $pos + 12, BigEndian;
    my $typecnt    = $tz.read-int32: $pos + 16, BigEndian;
    my $charcnt    = $tz.read-int32: $pos + 20, BigEndian;
    $pos += 24;

    # First we read the transition times (moments when a timezone changes
    # from one ruleset to another, e.g. daylight savings time, or changing
    # nominal zones, e.g. eastern to central).  These represent seconds
    # from the epoch.
    my int64 @transition-times;
    for ^$timecnt {
        @transition-times.push:
                $VERSION == 1
                ?? $tz.read-int32($pos, BigEndian)
                !! $tz.read-int64($pos, BigEndian);
        $pos += 4 * $VERSION; # 4 or 8
    }

    # Next, each one of these moments has an associated rule that
    # dictates, e.g., whether it's daylight savings time or how much
    # it is offset from GMT.
    my int8 @transition-time-local-time-type-as-index;
    for ^$timecnt {
        @transition-time-local-time-type-as-index.push($tz.read-int8: $pos);
        $pos += 1;
    }

    die "Invalid local time type referenced in transition time index."
        if @transition-time-local-time-type-as-index.any > $typecnt;

    # The following class will be used temporarily, as we'll add to it
    # later the information regarding standard/wall, universal/wall
    # and an actual string for the abbreviation.
    class TransTimeInfo {
        has int32 $.gmtoffset;
        has int8  $.is-dst;
        has uint8 $.abbr-index; # this is offset of the chars, sadly.
        method new(blob8 $b) {
            self.bless:
                    :gmtoffset($b.read-int32: 0, BigEndian),
                    :is-dst($b.read-int8:  4),
                    :abbr-index($b.read-uint8: 5)
        }
    }

    # Now we read in each of the ttinfos, or "Time Transition Information"
    # storing them temporarily until we can fully compose it.
    my @ttinfo-temp;
    for ^$typecnt {
        @ttinfo-temp.push: TransTimeInfo.new($tz.subbuf: $pos, 6);
        $pos += 6;
    }


    # Now we reach the timezone abbreviations, stored as the very annoying
    # C-style strings (\0 is the terminator/delimiter).
    # The hash will relate the index (see above) to the actual abbreviation
    # to aide final composition.
    my @tzabbr; # ignore this for now
    my %tz-abbr-temp;
    my $anchor = 0;
    while $anchor < $charcnt {
        my $tmp = 0;
        $tmp++ while $tz[$pos + $anchor + $tmp] != 0; # scan to the next null terminator
        %tz-abbr-temp{$anchor} := $tz.subbuf($pos + $anchor, $tmp).decode; # ASCII-encoded, so default UTF-8 is identical
        $anchor += $tmp + 1;
    }
    $pos += $anchor;

    # Collect leapseconds

    my LeapSecondInfo @leap-seconds;
    my $leap-length = $VERSION == 1 ?? 8 !! 12;
    for ^$leapcnt {
        @leap-seconds.push:
                LeapSecondInfo.new($tz.subbuf: $pos, $leap-length);
        $pos += $leap-length;
    }


    #Collect standard vs wall indicator indices, 1 = true";
    my Bool @ttisstd;
    for ^$ttisstdcnt {
        @ttisstd.push: so ( $tz[$pos] == 1);
        $pos++;
    }

    # Collect Universal/GMT vs local indicator indices, 1 = true";
    my Bool @ttisgmt;
    for ^$ttisstdcnt {
        @ttisgmt.push: so ($tz[$pos] == 1);
        $pos++;
    }

    # Now that the standard/wall, universal/local, and rulesets
    # have been collected, we can compose the actual transition time
    # informations (found in Classes.pm6)

    my @ttis;
    for ^$typecnt -> $i {
        @ttis.push:
            TransitionInfo.new:
                utoffset   => @ttinfo-temp[$i].gmtoffset,
                is-dst     => @ttinfo-temp[$i].is-dst == 1,
                abbr-index => @ttinfo-temp[$i].abbr-index,
                is-std     => @ttisstd[$i],
                is-gmt     => @ttisstd[$i],
                abbr       => (%tz-abbr-temp{@ttinfo-temp[$i].abbr-index} // '') # <-- TODO: this is a quick fix for America/Adak which isn't reading the strings properly
    }

    # Lastly, we determine the goback/goahead information
    # which lets it know if the time information wraps/repeats for
    # the gregorian calendar.
    my $go-back  = False;
    my $go-ahead = False;
    my &ttis_eq = sub (\a, \b) {
        so (a.utoffset   == b.utoffset)
        && (a.is-ut      && b.is-ut)
        && (a.is-dst     && b.is-dst)
        && (a.is-std     && b.is-std)
        && (a.abbr-index == b.abbr-index)
    }
    my &diff_by_repeat = sub (\a, \b) {
        # This has a guard for when sizes are different.
        # That won't be a problem for our implementation
        (a - b) == 12622780800; # avg s/y (31556952) x gregorian cycle (400y)
    }

    my $i;
    loop ($i = 1; $i < $timecnt; $i++) {
        my $ttis_eq = ttis_eq(
                @ttis[ @transition-time-local-time-type-as-index[$i]],
                @ttis[ @transition-time-local-time-type-as-index[ 0]]);
        my $diff_by_repeat = diff_by_repeat(
                @transition-times[$i],
                @transition-times[ 0]);
        if $ttis_eq && $diff_by_repeat {
            $go-back = True;
            last;
        }
    }
    loop ($i = $timecnt - 2; $i ≥ 0; $i--) {
        if &ttis_eq(@ttis[ @transition-time-local-time-type-as-index[$timecnt - 1]], @ttis[@transition-time-local-time-type-as-index[$i]])
        && &diff_by_repeat(@transition-times[$timecnt - 1], @transition-times[$i]) {
            $go-ahead = True;
            last;
        }
    }

    self.bless:
        leap-count => $leapcnt,
        time-count => $timecnt,
        type-count => $typecnt,
        char-count => $charcnt,
        go-back    => $go-back,
        go-ahead   => $go-ahead,
        ats        => @transition-times,
        types      => @transition-time-local-time-type-as-index,
        ttis       => @ttis,
        chars      => %tz-abbr-temp.pairs.sort(*.key.Int)>>.value.join(0.chr) ~ (0.chr), # restores the expected string
        lsis       => @leap-seconds,
        name       => $name
}