import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/data/tank_movement.dart';
import 'package:ulmgap/features/flight/flight_screen.dart';
import 'package:ulmgap/features/tank/tank_screen.dart';

import '../../support/fakes.dart';

final now = DateTime(2026, 10, 14, 10);
final instr = testUser(uid: 'ins', profile: 'instructeur', shortName: 'INS');

TankMovement mv(String id, String kind, int liters, String date, int after,
        {String? flightId, String? aircraftId, bool technical = false, String? note, DateTime? at}) =>
    TankMovement.fromMap(id, {
      'kind': kind, 'liters': liters, 'date': date, 'flightId': flightId,
      'aircraftId': aircraftId, 'technical': technical, 'note': note, 'by': 'ins',
      'at': at ?? DateTime(2026, 10, 14), 'litersAfter': after,
      if (kind == 'gauge') 'measuredLiters': after,
    });

FakeFlightApi flights() => FakeFlightApi()
  ..aircraft = [
    Aircraft.fromMap('a1', {'registration': 'F-JABC', 'label': 'ULM 1', 'active': true}),
    Aircraft.fromMap('a2', {'registration': 'F-JOLD', 'label': 'ULM 2', 'active': false}),
    Aircraft.fromMap('a3', {'registration': 'F-JXYZ', 'label': 'ULM 3', 'active': true}),
  ];

Widget host(AppUser me, FakeTankApi tank, {FakeFlightApi? api}) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      flights: api ?? flights(),
      finance: FakeFinanceApi(),
      tank: tank,
      child: MaterialApp(home: TankScreen(me: me, now: () => now)),
    );

FakeTankApi october() => FakeTankApi()
  ..level = 180
  ..movements = [
    mv('r', 'refill', 200, '2026-10-02', 200),
    mv('f1', 'flight', -15, '2026-10-05', 185, flightId: 'fl1', aircraftId: 'a1'),
    mv('f2', 'flight', -10, '2026-10-06', 175, flightId: 'fl2', aircraftId: 'a1', technical: true),
    mv('af', 'aircraft_fill', -20, '2026-10-08', 155, aircraftId: 'a1', note: 'Convoyage'),
    mv('g', 'gauge', 25, '2026-10-10', 180, note: 'Jauge'),
    mv('old', 'refill', 100, '2026-09-20', 100),
  ];

void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('titre, niveau actuel, mouvements du mois (plus récent d\'abord) et totaux',
      (tester) async {
    _useTallView(tester);
    await tester.pumpWidget(host(instr, october()));
    await tester.pump();
    expect(find.text('Suivi cuve'), findsOneWidget);
    expect(find.text('Niveau actuel : 180 L'), findsOneWidget);
    expect(find.text('Remplissage'), findsOneWidget); // celui de septembre est hors période
    expect(find.text('Vol — F-JABC'), findsOneWidget);
    expect(find.text('Vol — F-JABC (technique)'), findsOneWidget);
    expect(find.text('Plein hors vol — F-JABC'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Relevé de jauge'), findsOneWidget);
    expect(find.text('+200 L'), findsOneWidget);
    expect(find.text('−15 L'), findsOneWidget);
    expect(find.text('10/10/2026 · Jauge · Niveau après : 180 L'), findsOneWidget);
    expect(find.text('08/10/2026 · Convoyage · Niveau après : 155 L'), findsOneWidget);
    // Plus récent d'abord.
    expect(tester.getTopLeft(find.widgetWithText(ListTile, 'Relevé de jauge')).dy,
        lessThan(tester.getTopLeft(find.text('Remplissage')).dy));
    // Couleurs des litres signés.
    expect(tester.widget<Text>(find.text('+200 L')).style?.color, Colors.green.shade700);
    expect(tester.widget<Text>(find.text('−15 L')).style?.color,
        Theme.of(tester.element(find.text('−15 L'))).colorScheme.error);
    // Totaux de la période.
    expect(find.text('Remplissages : +200 L'), findsOneWidget);
    expect(find.text('Vols : −25 L (dont vols techniques : −10 L)'), findsOneWidget);
    expect(find.text('Pleins hors vol : −20 L'), findsOneWidget);
    expect(find.text('Écarts de jauge : +25 L'), findsOneWidget);
  });

  testWidgets('même jour : la saisie la plus récente d\'abord', (tester) async {
    _useTallView(tester);
    final tank = FakeTankApi()
      ..movements = [
        mv('a', 'refill', 50, '2026-10-05', 50, at: DateTime(2026, 10, 5, 8)),
        mv('b', 'gauge', -3, '2026-10-05', 47, at: DateTime(2026, 10, 5, 9)),
      ];
    await tester.pumpWidget(host(instr, tank));
    await tester.pump();
    expect(tester.getTopLeft(find.widgetWithText(ListTile, 'Relevé de jauge')).dy,
        lessThan(tester.getTopLeft(find.text('Remplissage')).dy));
  });

  testWidgets('niveau négatif : affiché en orange', (tester) async {
    await tester.pumpWidget(host(instr, FakeTankApi()..level = -12));
    await tester.pump();
    final t = tester.widget<Text>(find.text('Niveau actuel : −12 L'));
    expect(t.style?.color, Colors.orange.shade800);
  });

  testWidgets('aucun mouvement : message', (tester) async {
    await tester.pumpWidget(host(instr, FakeTankApi()));
    await tester.pump();
    expect(find.text('Aucun mouvement sur cette période.'), findsOneWidget);
  });

  testWidgets('appui sur une ligne de vol : fiche du vol', (tester) async {
    _useTallView(tester);
    final api = flights()
      ..directory = [member('u1', 'JDU', 'eleve')]
      ..flights = [
        testFlight(
            id: 'fl1', start: DateTime(2026, 10, 5, 9), crew: ['u1'], createdBy: 'u1',
            status: 'valide', isClosed: true, actualFlightMinutes: 60, billedAmount: 12000,
            billedTo: 'account'),
      ];
    await tester.pumpWidget(host(instr, october(), api: api));
    await tester.pump();
    await tester.tap(find.text('Vol — F-JABC'));
    await tester.pumpAndSettle();
    expect(find.byType(FlightScreen), findsOneWidget);
  });

  testWidgets('Plein d\'un appareil : appareils actifs, litres bornés, appel envoyé',
      (tester) async {
    final tank = FakeTankApi()..level = 180;
    await tester.pumpWidget(host(instr, tank));
    await tester.pump();
    await tester.tap(find.text('Plein d\'un appareil'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tank-aircraft')));
    await tester.pumpAndSettle();
    expect(find.text('ULM 2 (F-JOLD)'), findsNothing); // inactif
    await tester.tap(find.text('ULM 3 (F-JXYZ)').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tank-liters')), '101');
    await tester.tap(find.text('Valider'));
    await tester.pump();
    expect(find.text('Litres invalides (1 à 100).'), findsOneWidget);
    expect(tank.fills, isEmpty);
    await tester.enterText(find.byKey(const Key('tank-liters')), '20');
    await tester.enterText(find.byKey(const Key('tank-note')), 'Convoyage');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(tank.fills.single,
        {'aircraftId': 'a3', 'liters': 20, 'date': DateTime(2026, 10, 14), 'note': 'Convoyage'});
    expect(find.text('Opération enregistrée.'), findsOneWidget);
  });

  testWidgets('Relevé de jauge : niveau calculé rappelé, mesure envoyée', (tester) async {
    final tank = FakeTankApi()..level = 180;
    await tester.pumpWidget(host(instr, tank));
    await tester.pump();
    await tester.tap(find.text('Relevé de jauge'));
    await tester.pumpAndSettle();
    expect(find.text('Niveau calculé : 180 L'), findsOneWidget);
    await tester.tap(find.text('Valider'));
    await tester.pump();
    expect(find.text('Niveau mesuré invalide (0 à 100 000 L).'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tank-measured')), '172');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(tank.gauges.single, {'measuredLiters': 172, 'date': DateTime(2026, 10, 14), 'note': null});
  });

  testWidgets('erreur serveur : message dans le dialogue', (tester) async {
    final tank = FakeTankApi()..failWith = Exception('x');
    await tester.pumpWidget(host(instr, tank));
    await tester.pump();
    await tester.tap(find.text('Relevé de jauge'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tank-measured')), '172');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Opération incertaine : vérifiez la cuve avant de réessayer.'), findsOneWidget);
  });
}
