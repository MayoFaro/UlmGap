import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/csv.dart';
import 'package:ulmgap/core/formats.dart';
import 'package:ulmgap/core/money.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/admin/billing_report_screen.dart';

import '../../support/fakes.dart';

Widget host(FakeFinanceApi finance, FakeFlightApi flights, {DateTime Function()? now}) =>
    AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      finance: finance,
      flights: flights,
      child: MaterialApp(
        home: BillingReportScreen(now: now ?? () => DateTime(2026, 10, 15)),
      ),
    );

/// Le tableau (DataTable) dépasse la hauteur par défaut du banc de test.
void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('ne garde que les vols clôturés non supprimés de la période, avec les totaux',
      (tester) async {
    _useTallView(tester);
    final finance = FakeFinanceApi()
      ..flights = [
        testFlight(
            id: 'f1',
            start: DateTime(2026, 10, 5),
            aircraft: 'F-JABC',
            isClosed: true,
            billedAmount: 10000,
            billedTo: 'account'),
        testFlight(
            id: 'f2',
            start: DateTime(2026, 10, 6),
            aircraft: 'F-JXYZ',
            isClosed: true,
            billedAmount: 25000,
            billedTo: 'off_app'),
        testFlight(
            id: 'f3',
            start: DateTime(2026, 10, 7),
            aircraft: 'F-JQQQ',
            isClosed: false, // pas clôturé : exclu
            billedAmount: 5000,
            billedTo: 'account'),
        testFlight(
            id: 'f4',
            start: DateTime(2026, 10, 8),
            aircraft: 'F-JZZZ',
            isClosed: true,
            deleted: true, // supprimé : exclu
            billedAmount: 8000,
            billedTo: 'account'),
        testFlight(
            id: 'f5',
            start: DateTime(2026, 10, 9),
            aircraft: 'F-JABC',
            isClosed: true,
            billedAmount: 7000,
            billedTo: 'account'),
        testFlight(
            id: 'f6',
            start: DateTime(2026, 9, 30), // hors période (mois précédent)
            aircraft: 'F-JHORS',
            isClosed: true,
            billedAmount: 99999,
            billedTo: 'account'),
      ];
    final flightsApi = FakeFlightApi()..directory = [member('u1', 'DPS', 'instructeur')];

    await tester.pumpWidget(host(finance, flightsApi));
    await tester.pump();

    // f1, f2 et f5 seulement.
    expect(find.text('F-JABC'), findsNWidgets(2));
    expect(find.text('F-JXYZ'), findsOneWidget);
    expect(find.text('F-JQQQ'), findsNothing);
    expect(find.text('F-JZZZ'), findsNothing);
    expect(find.text('F-JHORS'), findsNothing);

    expect(find.text('Compte de DPS'), findsNWidgets(2)); // f1 et f5
    expect(find.text('Hors app'), findsOneWidget); // f2

    // Totaux : débité = 10000 + 7000 = 17000 ; hors app = 25000.
    expect(find.text(formatFcfa(17000)), findsOneWidget);
    expect(find.text(formatFcfa(25000)), findsWidgets); // ligne f2 + total hors app
  });

  testWidgets('aucun vol clôturé sur la période : message vide', (tester) async {
    _useTallView(tester);
    final finance = FakeFinanceApi()..flights = [];
    final flightsApi = FakeFlightApi();
    await tester.pumpWidget(host(finance, flightsApi));
    await tester.pump();
    expect(find.text('Aucun vol clôturé sur cette période.'), findsOneWidget);
  });

  testWidgets('le compte débité utilise payerUid quand il diffère du premier membre de l\'équipage',
      (tester) async {
    _useTallView(tester);
    final finance = FakeFinanceApi()
      ..flights = [
        testFlight(
          id: 'f1',
          start: DateTime(2026, 10, 5),
          crew: ['u1', 'u2'],
          payerUidField: 'u2',
          isClosed: true,
          billedAmount: 12000,
          billedTo: 'account',
        ),
      ];
    final flightsApi = FakeFlightApi()
      ..directory = [member('u1', 'DPS', 'instructeur'), member('u2', 'LDX', 'eleve')];
    await tester.pumpWidget(host(finance, flightsApi));
    await tester.pump();

    expect(find.text('Compte de LDX'), findsOneWidget);
    expect(find.text('Compte de DPS'), findsNothing);
  });

  test('billingCsvRows + buildCsv produit un contenu exact', () {
    final dir = {'u1': member('u1', 'DPS', 'instructeur')};
    final start = DateTime(2026, 10, 5, 9, 0);
    final end = DateTime(2026, 10, 5, 10, 30);
    final f = testFlight(
      id: 'f1',
      start: start,
      end: end,
      aircraft: 'F-JABC',
      isClosed: true,
      billedAmount: 12000,
      billedTo: 'account',
      actualFlightMinutes: 90,
    );

    final rows = billingCsvRows([f], dir);
    final csv = buildCsv(billingCsvHeaders, rows);

    final expectedHeader =
        'Date;Départ;Fin;Appareil;Équipage;Passagers;Mode;Durée réelle (min);Montant;Imputation;Compte débité';
    final expectedRow =
        '${formatDay(start)};${formatTime(start)};${formatTime(end)};F-JABC;DPS;;Standard;90;12000;Compte;DPS';
    expect(csv, '﻿$expectedHeader\r\n$expectedRow\r\n');
  });

  test('billingCsvRows : vol hors app sans compte débité', () {
    final dir = {'u1': member('u1', 'DPS', 'instructeur')};
    final f = testFlight(
      id: 'f1',
      passengers: const ['Ami sans compte'],
      isClosed: true,
      billedAmount: 30000,
      billedTo: 'off_app',
      pricingMode: 'custom',
    );

    final rows = billingCsvRows([f], dir);
    expect(rows.single[9], 'Hors app'); // imputation
    expect(rows.single[10], ''); // compte débité
  });
}
