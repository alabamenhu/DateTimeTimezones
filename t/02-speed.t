# Okay, this isn't actually a real test file.
# It's designed to judge the performance implications of using Timezone aware.
# Quantity to test
use Test;

my $q = 1000; # quantity to test;
say "Time results for $q new instances";

my $start = now;
my @a;
for 100_000_000..(100_000_000 + $q) -> $i {
    @a.push: DateTime.new: $i;
}
my $time1 = now - $start;
say "Original: ", $time1, "({@a.head.Str})";
use DateTime::Timezones;

$start = now;
my @b;
for 100_000_000..(100_000_000 + $q) -> $i {
    @b.push: DateTime.new: $i;
}
my $time2 = now - $start;

say "Tz--GMT: ", $time2, "({@b.head.Str} in {@b.head.tz-abbr})";

my @c;
for 100_000_000..(100_000_000 + $q) -> $i {
    @c.push: DateTime.new: $i, :timezone<America/Los_Angeles>;
}
my $time3 = now - $start;

say "Tz--PST: ", $time3, "({@c.head.Str} in {@c.head.tz-abbr})";
ok True;
done-testing;
