import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/crew_member.dart';
import 'package:ulmgap/data/flight.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/logbook/logbook_screen.dart';

import '../../support/fakes.dart';

final now = DateTime(2026, 10, 15, 12);

Widget host(
  AppUser me,
  List<Flight> flights, {
  void Function(Flight)? onOpen,
  List<CrewMember>? directory,
  DateTimeRange? pickedRange,
}) =>
    AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      finance: FakeFinanceApi()..flights = flights,
      flights: FakeFlightApi()
        ..directory = directory ??
            [member('u1', 'DPS', 'instructeur'), member('u2', 'LDX', 'eleve')],
      child: MaterialApp(
        home: LogbookScreen(
          me: me,
          now: () => now,
          onOpen: onOpen,
          pickRange: (_, __) async => pickedRange,
        ),
      ),
    );

Finder tileOf(String id) => find.byKey(Key('logbook-$id'));
String total(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('logbook-total'))).data!;

Future<void> choose(WidgetTester tester, String key, String item) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

final eleve = testUser(uid: 'u2', profile: 'eleve', shortName: 'LDX');
final instructeur = testUser(uid: 'u1', profile: 'instructeur', shortName: 'DPS');

final flights = [
  testFlight(id: 'oct-closed', start: DateTime(2026, 10, 10, 9), crew: ['u1', 'u2'],
      isClosed: true, actualFlightMinutes: 75),
  testFlight(id: 'oct-other-ac', start: DateTime(2026, 10, 11, 9), crew: ['u2'],
      aircraftId: 'a2', aircraft: 'F-JXYZ', isClosed: true, actualFlightMinutes: 60),
  testFlight(id: 'oct-open', start: DateTime(2026, 10, 12, 9), crew: ['u2']),
  testFlight(id: 'oct-dps', start: DateTime(2026, 10, 13, 9), crew: ['u1'],
      isClosed: true, actualFlightMinutes: 50),
  testFlight(id: 'sep-closed', start: DateTime(2026, 9, 20, 9), crew: ['u2'],
      isClosed: true, actualFlightMinutes: 30),
  testFlight(id: 'sep-open', start: DateTime(2026, 9, 21, 9), crew: ['u2']),
  testFlight(id: 'tomorrow', start: DateTime(2026, 10, 16, 9), crew: ['u2']),
];

void main() {
  testWidgets('pilote : mois en cours, ses vols tous appareils, total des vols clôturés',
      (tester) async {
    await tester.pumpWidget(host(eleve, flights));
    await tester.pumpAndSettle();
    expect(find.text('Octobre'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(find.byKey(const Key('pilot-filter')), findsNothing);
    for (final id in ['oct-closed', 'oct-other-ac', 'oct-open']) {
      expect(tileOf(id), findsOneWidget, reason: id);
    }
    for (final id in ['oct-dps', 'sep-closed', 'tomorrow']) {
      expect(tileOf(id), findsNothing, reason: id);
    }
    expect(total(tester), 'Temps de vol : 2 h 15'); // 75 + 60
  });

  testWidgets('choix d\'un autre mois, puis de l\'année entière', (tester) async {
    await tester.pumpWidget(host(eleve, flights));
    await tester.pumpAndSettle();
    await choose(tester, 'month-select', 'Septembre');
    expect(tileOf('sep-closed'), findsOneWidget);
    expect(tileOf('oct-closed'), findsNothing);
    expect(total(tester), 'Temps de vol : 0 h 30');

    await choose(tester, 'month-select', 'Année');
    expect(tileOf('sep-closed'), findsOneWidget);
    expect(tileOf('oct-closed'), findsOneWidget);
    expect(total(tester), 'Temps de vol : 2 h 45'); // 75 + 60 + 30
  });

  testWidgets('période précise : bornes incluses, les menus mois passent en attente',
      (tester) async {
    await tester.pumpWidget(host(eleve, flights,
        pickedRange: DateTimeRange(start: DateTime(2026, 9, 21), end: DateTime(2026, 10, 10))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('custom-period')));
    await tester.pumpAndSettle();
    expect(find.text('Du 21/09/2026 au 10/10/2026'), findsOneWidget);
    expect(tileOf('sep-open'), findsOneWidget);
    expect(tileOf('oct-closed'), findsOneWidget); // le 10, dernier jour inclus
    expect(tileOf('sep-closed'), findsNothing);
    expect(tileOf('oct-other-ac'), findsNothing);
    expect(find.text('Octobre'), findsNothing);
    expect(total(tester), 'Temps de vol : 1 h 15');

    // Revenir à un mois efface la période précise.
    await choose(tester, 'month-select', 'Octobre');
    expect(find.text('Période précise'), findsOneWidget);
    expect(tileOf('oct-other-ac'), findsOneWidget);
  });

  testWidgets('période précise annulée : rien ne change', (tester) async {
    await tester.pumpWidget(host(eleve, flights));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('custom-period')));
    await tester.pumpAndSettle();
    expect(find.text('Octobre'), findsOneWidget);
    expect(total(tester), 'Temps de vol : 2 h 15');
  });

  testWidgets('instructeur : lui-même par défaut, puis tous les pilotes, puis un autre',
      (tester) async {
    await tester.pumpWidget(host(instructeur, flights));
    await tester.pumpAndSettle();
    expect(tileOf('oct-dps'), findsOneWidget);
    expect(tileOf('oct-other-ac'), findsNothing);
    expect(total(tester), 'Temps de vol : 2 h 05'); // 75 + 50

    await choose(tester, 'pilot-filter', 'Tous les pilotes');
    expect(tileOf('oct-other-ac'), findsOneWidget);
    expect(total(tester), 'Temps de vol : 3 h 05'); // 75 + 60 + 50, vol à deux compté une fois

    await choose(tester, 'pilot-filter', 'LDX · Nom LDX');
    expect(tileOf('oct-dps'), findsNothing);
    expect(total(tester), 'Temps de vol : 2 h 15');
  });

  testWidgets('instructeur, annuaire vide : pas de plantage', (tester) async {
    await tester.pumpWidget(host(instructeur, flights, directory: const []));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(total(tester), 'Temps de vol : 2 h 05');
  });

  testWidgets('vols à clôturer : compteur toutes périodes, un appui les affiche',
      (tester) async {
    await tester.pumpWidget(host(eleve, flights));
    await tester.pumpAndSettle();
    expect(find.text('2 vols à clôturer'), findsOneWidget); // oct-open + sep-open
    expect(tileOf('sep-open'), findsNothing);

    await tester.tap(find.byKey(const Key('to-close-count')));
    await tester.pumpAndSettle();
    expect(tileOf('sep-open'), findsOneWidget);
    expect(tileOf('oct-open'), findsOneWidget);
    expect(tileOf('oct-closed'), findsNothing);

    await tester.tap(find.byKey(const Key('to-close-count')));
    await tester.pumpAndSettle();
    expect(tileOf('sep-open'), findsNothing);
    expect(tileOf('oct-closed'), findsOneWidget);
  });

  testWidgets('un appui ouvre le vol', (tester) async {
    Flight? opened;
    await tester.pumpWidget(host(eleve, flights, onOpen: (f) => opened = f));
    await tester.pumpAndSettle();
    await tester.tap(tileOf('oct-open'));
    expect(opened?.id, 'oct-open');
  });

  testWidgets('aucun vol : message vide et total à zéro', (tester) async {
    await tester.pumpWidget(host(eleve, const []));
    await tester.pumpAndSettle();
    expect(find.text('Aucun vol sur cette période.'), findsOneWidget);
    expect(total(tester), 'Temps de vol : 0 h 00');
  });

  testWidgets('plan 4b : atterrissages en haut, amerrissages seulement s\'il y en a',
      (tester) async {
    Flight closed(String id, int day, int landings, int water) => Flight.fromMap(id, {
          'start': DateTime(2026, 10, day, 9), 'end': DateTime(2026, 10, day, 10),
          'crew': ['u2'], 'status': 'valide', 'isClosed': true, 'deleted': false,
          'actualFlightMinutes': 60, 'landings': landings, 'waterLandings': water,
        });
    await tester.pumpWidget(host(eleve, [closed('a', 3, 2, 0), closed('b', 4, 1, 0)]));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('logbook-landings'))).data, 'Atterrissages : 3');

    await tester.pumpWidget(host(eleve, [closed('c', 3, 2, 0), closed('d', 4, 1, 2)]));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('logbook-landings'))).data,
        'Atterrissages : 3 · Amerrissages : 2');
  });
}
