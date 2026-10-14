import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/cash.dart';
import 'package:ulmgap/data/cash_movement.dart';

CashMovement m(String id, String kind, int amount, String date,
        {String? correctsId, String? userUid, int at = 0}) =>
    CashMovement.fromMap(id, {
      'kind': kind, 'amount': amount, 'date': date, 'correctsId': correctsId,
      'userUid': userUid, 'by': 'x', 'at': DateTime.fromMillisecondsSinceEpoch(at),
    });

void main() {
  test('types : codes, libellés, sens ; cinq filtres sans le Fond initial', () {
    expect(CashKind.fromCode('fuel_credit'), CashKind.fuelCredit);
    expect(CashKind.fromCode('inconnu'), isNull);
    expect(CashKind.fuelPurchase.label, 'Achat carburant');
    expect(CashKind.cashGap.sign, 0);
    expect(CashKind.filters, isNot(contains(CashKind.opening)));
    expect(CashKind.filters.length, 5);
  });

  test('cashDayCode', () {
    expect(cashDayCode(DateTime(2026, 3, 5, 18)), '2026-03-05');
  });

  test('montant juste : origine + corrections', () {
    final all = [
      m('a', 'maintenance', -86000, '2026-07-21'),
      m('c1', 'maintenance', 18000, '2026-07-21', correctsId: 'a'),
      m('b', 'maintenance', -1000, '2026-07-21'),
    ];
    expect(effectiveAmount(all[0], all), -68000);
    expect(effectiveAmount(all[2], all), -1000);
  });

  test('période : bornes [from, to[, filtre, tri date puis saisie décroissants', () {
    final all = [
      m('old', 'maintenance', -1, '2026-09-30'),
      m('a', 'fuel_credit', 10, '2026-10-01', at: 1),
      m('b', 'fuel_purchase', -5, '2026-10-01', at: 2),
      m('c', 'opening', 100, '2026-10-31'),
      m('next', 'fuel_credit', 1, '2026-11-01'),
    ];
    final from = DateTime(2026, 10, 1), to = DateTime(2026, 11, 1);
    expect(cashPeriod(all, from, to, {}).map((e) => e.id), ['c', 'b', 'a']);
    expect(cashPeriod(all, from, to, {CashKind.fuelCredit}).map((e) => e.id), ['a']);
  });

  test('totaux : selon le sens du type ; écart selon son signe ; corrections comprises', () {
    final t = cashTotals([
      m('a', 'fuel_credit', 50000, '2026-10-01'),
      m('c', 'fuel_credit', -20000, '2026-10-01', correctsId: 'a'),
      m('b', 'fuel_purchase', -10000, '2026-10-01'),
      m('g1', 'cash_gap', 3000, '2026-10-01'),
      m('g2', 'cash_gap', -1000, '2026-10-01'),
    ]);
    expect(t.entries, 33000);
    expect(t.exits, -11000);
  });

  test('titre : Crédit carburant XXX, sans adhérent pour une ligne importée', () {
    expect(cashTitle(m('a', 'fuel_credit', 1, '2026-10-01', userUid: 'u1'), {'u1': 'LCM'}),
        'Crédit carburant LCM');
    expect(cashTitle(m('a', 'fuel_credit', 1, '2026-10-01'), {}), 'Crédit carburant');
    expect(cashTitle(m('a', 'maintenance', -1, '2026-10-01'), {}), 'Maintenance');
  });

  test('Cashbox : document absent → vide, reprise en cours', () {
    expect(Cashbox.fromMap(null).balance, 0);
    expect(Cashbox.fromMap(null).migrationClosed, isFalse);
    expect(Cashbox.fromMap({'balance': 5, 'migrationClosedAt': DateTime(2026, 10, 20)}).migrationClosed,
        isTrue);
  });
}
