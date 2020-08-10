# DateTime::Timezones

An module to extend the built in `DateTime` with timezone support.
To use, simply include it at any point in your code:

```raku 
use DateTime::Timezones;

my $dt = DateTime.new: now;
```

This extends `DateTime` to include the following three new attributes whose names *are subject to change*.

  * **`.olson-id`** *(Str)*  
  The unique identifier for the timezone. 
  These are maintained by the IANA and based around city names, in the format of *Region/City*, and occasionally *Region/Subregion/City*. 
  They do not tend to align with popular usage.  In the United States, for instance, what is commonly called Eastern Time is listed as America/New_York).
  * **`.tz-abbr`** *(Str)*  
  An (mostly) unique abbreviation for the timezone. 
  It normally is more representative of popular usage (so *EST* for Eastern Standard Time in America/New_York) and normally differs based on daylight savings time.
  * **`.is-dst`** *(Bool)*  
  This value is `True` if the timezone is in what is commonly referred to as either Daylight Saving Time (hence the attribute name) or Summer Time where the timezone is shifted by (normally) one hour.
  The value is `False` during Standard time which in many timezones is the only possible value.


For the most part, once you enable it, you won't need to do anything different at all, as it is designed to be as discreet as possible.
There are, nonetheless, a few things to note:

 * The default time zone is either **Etc/GMT** *or*, if you have `Intl::UserTimezone`, the one indicated by `user-timezone`.
 * The attribute `timezone` has been modified slightly to be allomorphic. 
 For creation, you may pass either an `Int` offset *or* a `Str` Olson ID.
 Integer offsets are taken into account but the resultant time will be zoned to GMT (eventually whole-hour offsets will be be given an appropriate `Etc/` zone).  
 When accessing `.timezone`, you get an `IntStr` comprising the offset and the Olson ID, so it should Just Work™. 
 If you absolutely must have a strict `Int` value, use `.offset`, and for a strict `Str` value, use `.olson-id`
 * **(NYI)** The formatter has been changed to indicate the timezone.
 This makes it incompatible with RFC 3339.
 The `use` option 'rfc3339' will restore the original formatter.
 * Using `.later()` and `.earlier()` methods are currently untested.
 You may get unexpected results if you use them and cross a timezone transition.
 
### Leapseconds

Leapseconds are annoying for timekeeping and POSIX explicitly ignores them since future ones are unpredictable because weird physics.
I do not have the expertise to ensure that leapseconds are handled correctly, but welcome any code review and/or pull requests to remedy this (particularly test cases).

## How does it work?

While the module initially planned on `augment`ing `DateTime`, it turns out that has significant problems for things like precompilation (you can't) and requires enabling `MONKEY-TYPING` which just feels dirty.

Instead, `DateTime.new` is wrapped with a new method that returns the same (or functionally the same) `DateTime` you would have expected and mixes in the parameterized `TimezoneAware` role. 
It has a few tricks to make sure it doesn't apply the role multiple times.

The data files come from the [IANA](https://www.iana.org/time-zones), and are compiled using their zone information compiler (ZIC). 

## Version history
  - **0.3**  
    - Support for 'upgrading' timezone-unaware `DateTime` objects that may have been precompiled before this module's `use` statement.
    - Additional test files.
    - Added an example: see `world-clock.raku` and pass in your favorite timezones
  - **0.2.1**  
    - Fixed creation from Instants by adding `.floor`
  - **0.2**  
    - TZif files generated on our own directly from the TZ database.
    - Fixed error in parsing leapseconds from TZif files
    - Fixed offset calculation error caused by misreading C code
    - Added test files (but more are needed, esp for leapseconds)
    - Created automated updater script for ease of maintenance.
  - **0.1**  
    - First release.
    - Basic support for creation of `DateTime` with timezone information.