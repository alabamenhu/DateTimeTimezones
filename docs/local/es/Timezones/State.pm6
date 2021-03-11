#| Las reglas para un huso horario y segundos intercalares que le corresponden
unit class State;
use DateTime::Timezones::Classes;

has int16 $.leap-count = 0;     #= Número de segundos intercalares (es decir, +@!lsis)
has int16 $.time-count = 0;     #= Número de momentos transitorios (es decir, +@!ats)
has int16 $.type-count = 0;     #= Número de objetos de horas locales (TimeInfo)
has int16 $.char-count = 0;     #= Número de caracteres en las cadenas abreviaturas (es decir, @!chars.join.chars)
has Bool  $.go-back    = False; #= Si las reglas se repiten en el futuro.
has Bool  $.go-ahead   = False; #= Si las reglas se repiten en el pasado.
has str   $.chars      = "";    #= Las cadenas abreviaturaTime zone abbreviation strings (null delimited)
has int64 @.ats;                #= Los momentos cuando el huso realiza transición
has int16 @.types;              #= La regla que corresponde a cada momento de transición (para habilitar @!ats Z @!types)
has TransitionInfo @.ttis;      #= Las reglas para la hora de transición, indicando segundos de desfase (Transition time information structure)
has LeapSecondInfo @.lsis;      #= Los segundos intercalares para este timezoneThe leap seconds for this timezone.
has str $.name;

#| Crea un nuevo State desde un archivo TZ
method new (blob8 $tz, :$name) { ... }