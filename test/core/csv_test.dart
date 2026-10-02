import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/csv.dart';

void main() {
  test('BOM, en-tête et séparateur point-virgule', () {
    final csv = buildCsv(['A', 'B'], [
      ['1', '2'],
      ['3', '4'],
    ]);
    expect(csv, '﻿A;B\r\n1;2\r\n3;4\r\n');
  });

  test('sans ligne : BOM et en-tête seuls', () {
    final csv = buildCsv(['A', 'B'], []);
    expect(csv, '﻿A;B\r\n');
  });

  test('un champ contenant le séparateur est encadré de guillemets', () {
    final csv = buildCsv(['Nom'], [
      ['Dupont; Jean'],
    ]);
    expect(csv, '﻿Nom\r\n"Dupont; Jean"\r\n');
  });

  test('un champ contenant des guillemets : guillemets doublés et champ encadré', () {
    final csv = buildCsv(['Phrase'], [
      ['Il dit "bonjour"'],
    ]);
    expect(csv, '﻿Phrase\r\n"Il dit ""bonjour"""\r\n');
  });

  test('un champ contenant un saut de ligne est aussi échappé', () {
    final csv = buildCsv(['X'], [
      ['a\nb'],
    ]);
    expect(csv, '﻿X\r\n"a\nb"\r\n');
  });

  test('un champ ordinaire n\'est pas modifié', () {
    final csv = buildCsv(['X'], [
      ['ULM 1'],
    ]);
    expect(csv, '﻿X\r\nULM 1\r\n');
  });
}
