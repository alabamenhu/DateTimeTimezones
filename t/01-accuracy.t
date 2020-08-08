use DateTime::Timezones::Routines;
use DateTime::Timezones::Classes;
use Test;

# Known GMT times
# 1577934245 : 2020-01-02 03:04:05
# 1589025600 :
#  467372577 : 1984-10-23 09:42:57
#  703723256 : 1992-04-19 22:40:56


sub time-cmp(Time \a, Time \b) {
    if    a.year   != b.year   { return a.year   < b.year   ?? -1 !! 1 }
    elsif a.month  != b.month  { return a.month  < b.month  ?? -1 !! 1 }
    elsif a.day    != b.day    { return a.day    < b.day    ?? -1 !! 1 }
    elsif a.hour   != b.hour   { return a.hour   < b.hour   ?? -1 !! 1 }
    elsif a.minute != b.minute { return a.minute < b.minute ?? -1 !! 1 }
    elsif a.second != b.second { return a.second < b.second ?? -1 !! 1 }
    else { return 0 }
}

my $g1 = Time.new(second => 5, minute => 4, hour => 3, day => 2, month => 0, year => 120, weekday => 4, yearday => 1, dst => 0, gmt-offset => 0, tz-abbr => "GMT");
my $a1 = Time.new(second => 5, minute => 4, hour => 22, day => 1, month => 0, year => 120, weekday => 3, yearday => 0, dst => 0, gmt-offset => -18000, tz-abbr => "EST");
my $g2 = Time.new(second => 57, minute => 42, hour => 9, day => 23, month => 9, year => 84, weekday => 2, yearday => 296, dst => 0, gmt-offset => 0, tz-abbr => "GMT");
my $a2 = Time.new(second => 57, minute => 42, hour => 5, day => 23, month => 9, year => 84, weekday => 2, yearday => 296, dst => 1, gmt-offset => -14400, tz-abbr => "EDT");
my $g3 = Time.new(second => 56, minute => 40, hour => 22, day => 19, month => 3, year => 92, weekday => 0, yearday => 109, dst => 0, gmt-offset => 0, tz-abbr => "GMT");
my $a3 = Time.new(second => 56, minute => 40, hour => 18, day => 19, month => 3, year => 92, weekday => 0, yearday => 109, dst => 1, gmt-offset => -14400, tz-abbr => "EDT");


my $gmt = get-timezone-data('Etc/GMT');
my $atl = get-timezone-data('America/New_York');

subtest "POSIX time to local times" => {
    plan 6;
    is time-cmp($g1, localtime($gmt, 1577934245)), 0, "GMT";
    is time-cmp($g2, localtime($gmt,  467372577)), 0, "GMT";
    is time-cmp($g3, localtime($gmt,  703723256)), 0, "GMT";
    is time-cmp($a1, localtime($atl, 1577934245)), 0, "EST";
    is time-cmp($a2, localtime($atl,  467372577)), 0, "EDT";
    is time-cmp($a3, localtime($atl,  703723256)), 0, "EDT";
}

subtest "Local times to POSIX time" => {
    plan 6;
    is gmt-from-local($gmt, $g1), 1577934245;
    is gmt-from-local($gmt, $g2), 467372577;
    is gmt-from-local($gmt, $g3), 703723256;
    is gmt-from-local($atl, $a1), 1577934245;
    is gmt-from-local($atl, $a2), 467372577;
    is gmt-from-local($atl, $a3), 703723256;
}

done-testing;
