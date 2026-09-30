// Génération CSV pure (Task 12, relevé des vols facturés) : séparateur `;`,
// fin de ligne `\r\n`, BOM UTF-8 en tête (pour qu'Excel détecte l'encodage).
// Le téléchargement proprement dit vit dans core/download.dart.
const _bom = '﻿';

/// Échappe un champ si besoin (contient le séparateur, un guillemet ou un
/// saut de ligne) : encadré de guillemets, guillemets internes doublés.
String _field(String value) {
  final needsQuoting =
      value.contains(';') || value.contains('"') || value.contains('\n') || value.contains('\r');
  if (!needsQuoting) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// Contenu CSV complet : BOM, ligne d'en-tête puis une ligne par élément de
/// [rows]. Chaque ligne de [rows] doit avoir la même longueur que [headers].
String buildCsv(List<String> headers, List<List<String>> rows) {
  final buffer = StringBuffer(_bom);
  void writeRow(List<String> row) {
    buffer.write(row.map(_field).join(';'));
    buffer.write('\r\n');
  }

  writeRow(headers);
  for (final row in rows) {
    writeRow(row);
  }
  return buffer.toString();
}
