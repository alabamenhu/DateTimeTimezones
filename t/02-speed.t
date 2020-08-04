# Okay, this isn't actually a real test file.
# It's designed to judge the performance implications of using Timezone aware.
# Quantity to test
my $q = 100; # quantity to test;

my $start = now;
my $a;
for 100_000_000..(100_000_000 + $q) -> $i {
    $a = DateTime.new: $i;
}
my $time1 = now - $start;
use DateTime::Timezones;
$start = now;
my $b;
for 100_000_000..(100_000_000 + $q) -> $i {
    $b = DateTime.new: $i;
}
my $time2 = now - $start;

say "Time results for $q new instances";
say "Original: ", $time1;
say "Timezone: ", $time2;
