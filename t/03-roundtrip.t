use DateTime::Timezones::Routines;
use Test;
my @timezones = <Etc/GMT America/New_York America/Los_Angeles Europe/Madrid
                 Asia/Tokyo Africa/Kinshasa Africa/Mogadishu Asia/Qatar Asia/Singapore>;

for ^25 {
    my $timezone = get-timezone-data @timezones.roll;
    my $in = (^1700000000).roll;

    my $mid = localtime $timezone, $in;
    my $out = gmt-from-local $timezone, $mid;

    is $in, $out, "Random test ($in)";
}
done-testing;