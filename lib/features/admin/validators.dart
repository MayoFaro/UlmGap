// Mêmes règles que functions/src/admin/validation.ts (le serveur reste l'autorité).
final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _shortRe = RegExp(r'^[A-Z0-9]{2,4}$');

String? validateEmail(String v) =>
    _emailRe.hasMatch(v.trim()) ? null : 'E-mail invalide.';

String? validateShortName(String v) => _shortRe.hasMatch(v.trim().toUpperCase())
    ? null
    : '2 à 4 lettres ou chiffres.';

String? validateRequired(String v, String field) =>
    v.trim().isEmpty ? '$field obligatoire.' : null;
