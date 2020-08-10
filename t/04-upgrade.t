use Test;

# This is about the only way that it's possible for an
# old fashioned DateTime to be made.  Each one will be
# tested that it upgrades properly based on its mutability
my $olson1 = BEGIN DateTime.new: now;
my \olson2 = BEGIN DateTime.new: now;
my $abbr1  = BEGIN DateTime.new: now;
my \abbr2  = BEGIN DateTime.new: now;
my $dst1   = BEGIN DateTime.new: now;
my \dst2   = BEGIN DateTime.new: now;

# All new timezones should be TimezoneAware
use DateTime::Timezones;

# First check whether mutable containers are correctly upgraded
try {
    $olson1.olson-id;
    ok $olson1 ~~ Timezones::TimezoneAware, "Mutable upgrade for Olson ID";
    CATCH { ok False, "Mutable upgrade for Olson ID" }
}
try {
    $abbr1.tz-abbr;
    ok $abbr1 ~~ Timezones::TimezoneAware, "Mutable upgrade for TZ abbreviation";
    CATCH { ok False, "Mutable upgrade for TZ abbreviation" }
}
try {
    $dst1.is-dst;
    ok $dst1 ~~ Timezones::TimezoneAware, "Mutable upgrade for DST status";
    CATCH { ok False, "Mutable upgrade for DST status" }
}

# Next, check whether inmutables still provide nominally correct values
try {
    olson2.olson-id;
    ok olson2.olson-id ~~ Str, "Inmutable upgrade for Olson ID";
    CATCH { ok False, "Inmutable upgrade for Olson ID"}
}
try {
    abbr2.tz-abbr;
    ok abbr2.tz-abbr ~~ Str, "Mutable upgrade for TZ abbreviation";
    CATCH { ok False, "Inmutable upgrade for TZ abbreviation" }
}
try {
    dst2.is-dst;
    ok dst2.is-dst ~~ Bool, "Inmutable upgrade for DST status";
    CATCH { ok False, "Inmutable upgrade for DST status" }
}

done-testing;