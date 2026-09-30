import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/crew_member.dart';
import 'package:ulmgap/data/flight.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/counters/counters_screen.dart';

import '../../support/fakes.dart';

Widget host(AppUser me, List<Flight> flights, {List<CrewMember>? directory}) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      finance: FakeFinanceApi()..flights = flights,
      flights: FakeFlightApi()
        ..directory = directory ??
            [member('u1', 'DPS', 'instructeur'), member('u2', 'LDX', 'eleve')]
        ..aircraft = const [
          Aircraft(id: 'a0', registration: 'F-JOLD', label: 'ULM 0', active: false),
          Aircraft(id: 'a1', registration: 'F-JABC', label: 'ULM 1', active: true),
          Aircraft(id: 'a2', registration: 'F-JXYZ', label: 'ULM 2', active: true),
        ],
      child: MaterialApp(home: CountersScreen(me: me, now: () => DateTime(2026, 10, 15, 12))),
    );

String total(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

final flights = [
  testFlight(id: 'a', start: DateTime(2026, 3, 1, 9), crew: ['u1', 'u2'], aircraftId: 'a1',
      isClosed: true, actualFlightMinutes: 75),
  testFlight(id: 'b', start: DateTime(2026, 9, 1, 9), crew: ['u2'], aircraftId: 'a2',
      isClosed: true, actualFlightMinutes: 60),
  testFlight(id: 'c', start: DateTime(2026, 9, 2, 9), crew: ['u1'], aircraftId: 'a1',
      isClosed: true, actualFlightMinutes: 50),
  testFlight(id: 'unclosed', start: DateTime(2026, 9, 3, 9), crew: ['u2'], aircraftId: 'a1'),
  testFlight(id: 'deleted', start: DateTime(2026, 9, 4, 9), crew: ['u2'], aircraftId: 'a1',
      isClosed: true, deleted: true, actualFlightMinutes: 600),
  testFlight(id: 'last-year', start: DateTime(2025, 12, 31, 9), crew: ['u2'], aircraftId: 'a1',
      isClosed: true, actualFlightMinutes: 600),
];

void main() {
  testWidgets('élève : son total de l\'année, sans choix du pilote', (tester) async {
    await tester.pumpWidget(host(testUser(uid: 'u2', profile: 'eleve', shortName: 'LDX'), flights));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pilot-select')), findsNothing);
    expect(total(tester, 'pilot-total'), 'Total : 2 h 15'); // 75 + 60
  });

  testWidgets('instructeur : choisit le pilote, lui-même par défaut', (tester) async {
    await tester.pumpWidget(
        host(testUser(uid: 'u1', profile: 'instructeur', shortName: 'DPS'), flights));
    await tester.pumpAndSettle();
    expect(total(tester, 'pilot-total'), 'Total : 2 h 05'); // 75 + 50

    await tester.tap(find.byKey(const Key('pilot-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LDX · Nom LDX').last);
    await tester.pumpAndSettle();
    expect(total(tester, 'pilot-total'), 'Total : 2 h 15');
  });

  testWidgets('appareil : premier actif par défaut, puis au choix', (tester) async {
    await tester.pumpWidget(host(testUser(uid: 'u2', profile: 'eleve'), flights));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appareil'));
    await tester.pumpAndSettle();
    expect(find.text('ULM 1 (F-JABC)'), findsOneWidget);
    expect(total(tester, 'aircraft-total'), 'Total : 2 h 05'); // a : 75 + c : 50

    await tester.tap(find.byKey(const Key('aircraft-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ULM 2 (F-JXYZ)').last);
    await tester.pumpAndSettle();
    expect(total(tester, 'aircraft-total'), 'Total : 1 h 00');
  });

  testWidgets('période : année en cours par défaut', (tester) async {
    await tester.pumpWidget(host(testUser(uid: 'u2', profile: 'eleve'), flights));
    await tester.pumpAndSettle();
    expect(find.textContaining('Du jeudi 1 janvier'), findsOneWidget);
    expect(find.textContaining('Au jeudi 31 décembre'), findsOneWidget);
  });

  testWidgets('annuaire vide : pas de plantage, total du compte connecté', (tester) async {
    await tester.pumpWidget(host(
        testUser(uid: 'u1', profile: 'instructeur'), flights, directory: const []));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(total(tester, 'pilot-total'), 'Total : 2 h 05');
  });
}
