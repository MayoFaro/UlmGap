import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/formats.dart';

void main() {
  test('jour, heure, créneau en français', () {
    final a = DateTime(2026, 10, 12, 9, 5);
    expect(formatDay(a), 'lundi 12 octobre');
    expect(formatTime(a), '09:05');
    expect(formatRange(a, DateTime(2026, 10, 12, 10, 0)), '09:05–10:00');
    expect(dayOf(a), DateTime(2026, 10, 12));
  });

  test('formatMonth : nom du mois avec majuscule', () {
    expect(formatMonth(1), 'Janvier');
    expect(formatMonth(8), 'Août');
    expect(formatMonth(12), 'Décembre');
  });

  test('formatShortDate : jj/mm/aaaa', () {
    expect(formatShortDate(DateTime(2026, 9, 3)), '03/09/2026');
  });
}
