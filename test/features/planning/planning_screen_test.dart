import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/planning/planning_screen.dart';

import '../../support/fakes.dart';

final now = DateTime(2026, 10, 12, 8);

Widget host(FakeFlightApi api, AppUser me) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      flights: api,
      child: MaterialApp(home: Scaffold(body: PlanningScreen(me: me, now: () => now))),
    );

FakeFlightApi api() => FakeFlightApi()
  ..directory = [member('u1', 'JDU', 'eleve'), member('ins', 'INS', 'instructeur')]
  ..aircraft = [
    Aircraft.fromMap('a1', {'registration': 'F-JABC', 'label': 'ULM 1', 'active': true}),
    Aircraft.fromMap('a2', {'registration': 'F-JXYZ', 'label': 'ULM 2', 'active': true}),
  ];

void main() {
  testWidgets('vols groupés par jour, statut, équipage ; annulés masqués', (tester) async {
    final a = api()
      ..flights = [
        testFlight(id: 'v', start: DateTime(2026, 10, 12, 9), crew: ['u1', 'ins']),
        testFlight(id: 'd', start: DateTime(2026, 10, 13, 9), status: 'demande',
            crew: ['u1', 'ins'], instructorUid: 'ins', aircraftId: 'a2', aircraft: 'F-JXYZ'),
        testFlight(id: 'x', start: DateTime(2026, 10, 13, 14), deleted: true, aircraft: 'F-DEL'),
      ];
    await tester.pumpWidget(host(a, testUser(uid: 'u1')));
    await tester.pumpAndSettle();
    expect(find.text('lundi 12 octobre'), findsOneWidget);
    expect(find.text('mardi 13 octobre'), findsOneWidget);
    expect(find.textContaining('09:00–10:00 · F-JABC'), findsOneWidget);
    expect(find.text('Validé'), findsOneWidget);
    expect(find.textContaining('JDU/INS'), findsWidgets);
    expect(find.textContaining('F-DEL'), findsNothing);
  });

  testWidgets('rubriques « À valider » (instructeur désigné) et « Mes demandes »', (tester) async {
    final a = api()
      ..flights = [
        testFlight(id: 'd', start: DateTime(2026, 10, 13, 9), status: 'demande',
            crew: ['u1', 'ins'], instructorUid: 'ins'),
      ];
    await tester.pumpWidget(host(a, testUser(uid: 'ins', profile: 'instructeur', shortName: 'INS')));
    await tester.pumpAndSettle();
    expect(find.text('À valider'), findsOneWidget);
    expect(find.text('Mes demandes'), findsNothing);

    await tester.pumpWidget(host(a, testUser(uid: 'u1')));
    await tester.pumpAndSettle();
    expect(find.text('À valider'), findsNothing);
    expect(find.text('Mes demandes'), findsOneWidget);
  });

  testWidgets('demande expirée : affichée refusée, hors « À valider »', (tester) async {
    final a = api()
      ..flights = [
        testFlight(id: 'd', start: DateTime(2026, 10, 12, 7), status: 'demande',
            crew: ['u1', 'ins'], instructorUid: 'ins'),
      ];
    await tester.pumpWidget(host(a, testUser(uid: 'ins', profile: 'instructeur')));
    await tester.pumpAndSettle();
    expect(find.text('À valider'), findsNothing);
    expect(find.text('Refusé'), findsOneWidget);
  });

  testWidgets('filtre par appareil', (tester) async {
    final a = api()
      ..flights = [
        testFlight(id: 'v1', start: DateTime(2026, 10, 12, 9)),
        testFlight(id: 'v2', start: DateTime(2026, 10, 12, 11), aircraftId: 'a2', aircraft: 'F-JXYZ'),
      ];
    await tester.pumpWidget(host(a, testUser()));
    await tester.pumpAndSettle();
    expect(find.textContaining('F-JXYZ'), findsOneWidget);
    await tester.tap(find.byKey(const Key('aircraft-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ULM 1 (F-JABC)').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('F-JXYZ'), findsNothing);
    expect(find.textContaining('09:00–10:00 · F-JABC'), findsOneWidget);
  });

  testWidgets('vide et erreur', (tester) async {
    await tester.pumpWidget(host(api(), testUser()));
    await tester.pumpAndSettle();
    expect(find.text('Aucun vol à venir.'), findsOneWidget);

    await tester.pumpWidget(host(api()..error = Exception('refus'), testUser()));
    await tester.pumpAndSettle();
    expect(find.text('Impossible de charger les données. Vérifiez la connexion.'), findsOneWidget);
  });
}
