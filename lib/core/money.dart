// Format des montants (décision 6, miroir de rules/pricing.ts#formatFcfa) :
// groupes de 3 chiffres séparés par une espace insécable, sans décimales,
// signe « − » (U+2212) pour un montant négatif.
const _minusSign = '−';
const _nbsp = ' ';

String formatFcfa(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(_nbsp);
    buffer.write(digits[i]);
  }
  final sign = amount < 0 ? _minusSign : '';
  return '$sign$buffer${_nbsp}FCFA';
}

/// Analyse un montant saisi (espaces normales ou insécables acceptées comme
/// séparateurs de milliers). Rend `null` si vide, non entier, ou décimal.
int? parseAmount(String input) {
  final cleaned = input.replaceAll(_nbsp, '').replaceAll(' ', '').trim();
  if (cleaned.isEmpty) return null;
  if (!RegExp(r'^-?\d+$').hasMatch(cleaned)) return null;
  return int.tryParse(cleaned);
}
