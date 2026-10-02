// Format des montants (décision 6, miroir de rules/pricing.ts#formatFcfa) :
// groupes de 3 chiffres séparés par une espace insécable, sans décimales,
// signe « − » (U+2212) pour un montant négatif.
import 'package:flutter/services.dart';

const _minusSign = '−';
const _nbsp = ' ';

String _group(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(_nbsp);
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String formatFcfa(int amount) {
  final sign = amount < 0 ? _minusSign : '';
  return '$sign${_group(amount.abs().toString())}${_nbsp}FCFA';
}

/// Valeur d'un champ de saisie de montant : « 40 000 », « -5 000 » (tiret
/// ASCII, relu par [parseAmount]), sans unité.
String formatAmountInput(int amount) =>
    '${amount < 0 ? '-' : ''}${_group(amount.abs().toString())}';

/// Champ de montant : regroupe les chiffres par milliers pendant la saisie
/// (« 350000 » s'affiche « 350 000 »), garde un « - » en tête, ignore tout
/// autre caractère. Le curseur est replacé en fin de saisie.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.trim();
    final negative = raw.startsWith('-') || raw.startsWith(_minusSign);
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final text = '${negative ? '-' : ''}${_group(digits)}';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Analyse un montant saisi (espaces normales ou insécables acceptées comme
/// séparateurs de milliers). Rend `null` si vide, non entier, ou décimal.
int? parseAmount(String input) {
  final cleaned = input.replaceAll(_nbsp, '').replaceAll(' ', '').trim();
  if (cleaned.isEmpty) return null;
  if (!RegExp(r'^-?\d+$').hasMatch(cleaned)) return null;
  return int.tryParse(cleaned);
}
