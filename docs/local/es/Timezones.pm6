=begin pod
    =NAME DateTime::Timezones
    =AUTHOR Matthew Stephen Stuckwisch
    =TRANSLATOR Matéu Estebánicu Stuckwisch l’Alabameñu
    =VERSION 0.3.5
    =TITLE DateTime::Timezones
    =SUBTITLE Un módulo que habilita los husos horarios en Raku

    =begin quote
        Phileas Fogg avait, «sans s'en douter», gagné un jour sur son itinéraire, - et cela uniquement parce qu'il avait fait le tour du monde en allant vers l'est, et il eût, au contraire, perdu un jour en allant en sens inverse, soit vers l'ouest.
        — *Le Tour du monde en quatre-vingts jours* (Jules Vernes)
    =end quote

    Un módulo para extender el C<DateTime> interno con los husos horarios.
    Para usar, en algún lugar en tu código, incluye

    =begin code
        use DateTime::Timezones;

        my $dt = DateTime.new: now;
    =end code

=end pod

#| Un módulo que habilita los husos horarios en Raku
unit module Timezones;

#| Papel que entiende los husos horarios
role TimezoneAware[$olson = "Etc/GMT", $abbr = "GMT", $dst = False] {

    #| La etiqueta única (Olson) para identificar este huso
    method olson-id (-->  Str) { ... }
    #| La abreviatura para este huso que no tiene que ser única pero es más representativo del uso cotidiano
    method tz-abbr  (-->  Str) { ... }
    #| Si es horario estival
    method is-dst   (--> Bool) { ... }
}

# These are internal use only.  But if they weren't, they'd look like this:

#| Los DateTime que no entienden los husos
subset NotTimezoneAware of DateTime where * !~~ TimezoneAware;

use DateTime::Timezones::Routines;
