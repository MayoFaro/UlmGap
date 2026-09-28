import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/flight/flight_detail_screen.dart';

import '../../support/fakes.dart';

final now = DateTime(2026, 10, 12, 8);

Widget host(FakeFlightApi api, AppUser me, String id) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      flights: api,
      child: MaterialApp(home: FlightDetailScreen(flightId: id, me: me, now: () => now)),
    );

FakeFlightApi api() => FakeFlightApi()
  ..directory = [member('u1', 'JDU', 'eleve'), member('ins', 'INS', 'instructeur')]
  ..flights = [
    testFlight(
        id: 'd', start: DateTime(2026, 10, 13, 9), status: 'demande',
        crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins'),
    testFlight(
        id: 'old', start: DateTime(2026, 10, 12, 7), status: 'demande',
        crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins'),
  ];

/// Le contenu (fiche + actions) dépasse la fenêtre de test par défaut
/// (800x600 logique) : sans agrandir la vue, les éléments en bas de la
/// ListView (Tarification, boutons d'action) ne sont jamais construits par
/// la sliver list et les taps échouent, indépendamment du code de l'écran.
void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('informations et payeur', (tester) async {
    _useTallView(tester);
    await tester.pumpWidget(host(api(), testUser(uid: 'u1'), 'd'));
    await tester.pumpAndSettle();
    expect(find.text('mardi 13 octobre'), findsOneWidget);
    expect(find.text('09:00–10:00'), findsOneWidget);
    expect(find.text('F-JABC'), findsOneWidget);
    expect(find.text('Lomé'), findsOneWidget);
    expect(find.text('Demande'), findsOneWidget);
    expect(find.text('Payeur'), findsOneWidget);
    expect(find.text('Instructeur désigné : INS'), findsOneWidget);
  });

  testWidgets('refus avec motif par l\'instructeur désigné', (tester) async {
    _useTallView(tester);
    final a = api();
    await tester.pumpWidget(host(a, testUser(uid: 'ins', profile: 'instructeur'), 'd'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refuser'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('refuse-reason')), 'Météo');
    await tester.tap(find.text('Refuser').last);
    await tester.pumpAndSettle();
    expect(a.refused['d'], 'Météo');
  });

  testWidgets('annulation confirmée par le créateur', (tester) async {
    _useTallView(tester);
    final a = api();
    await tester.pumpWidget(host(a, testUser(uid: 'u1'), 'd'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler le vol'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oui, annuler'));
    await tester.pumpAndSettle();
    expect(a.cancelled, ['d']);
  });

  testWidgets('demande expirée : « Refusé (non validée avant le départ) », aucune action', (tester) async {
    _useTallView(tester);
    await tester.pumpWidget(host(api(), testUser(uid: 'ins', profile: 'instructeur'), 'old'));
    await tester.pumpAndSettle();
    expect(find.text('Refusé (non validée avant le départ)'), findsOneWidget);
    expect(find.text('Valider'), findsNothing);
    expect(find.text('Refuser'), findsNothing);
  });

  testWidgets('vol introuvable', (tester) async {
    await tester.pumpWidget(host(api(), testUser(), 'nope'));
    await tester.pumpAndSettle();
    expect(find.text('Vol introuvable.'), findsOneWidget);
  });
}
