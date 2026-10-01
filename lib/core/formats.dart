// Formats de date en français, sans dépendre des données de locale d'intl.
const _days = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// « lundi 12 octobre »
String formatDay(DateTime d) => '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// « Janvier » ([month] de 1 à 12).
String formatMonth(int month) {
  final m = _months[month - 1];
  return m[0].toUpperCase() + m.substring(1);
}

/// « 03/09/2026 »
String formatShortDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// « 09:05 »
String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// « 09:00–10:00 »
String formatRange(DateTime a, DateTime b) => '${formatTime(a)}–${formatTime(b)}';

/// Minuit (heure locale) du jour de [d].
DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
