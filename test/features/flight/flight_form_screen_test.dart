import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/profiles.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/flight.dart';
import 'package:ulmgap/data/flight_api.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/flight/flight_form_screen.dart';

import '../../support/fakes.dart';

final now = DateTime(2026, 10, 12, 8, 20);

Widget host(FakeFlightApi api, AppUser me,
        {Flight? flight, FlightFormMode mode = FlightFormMode.create}) =>
    AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      flights: api,
      child: MaterialApp(
          home: FlightFormScreen(me: me, flight: flight, mode: mode, now: () => now)),
    );

FakeFlightApi api() => FakeFlightApi()
  ..directory = [
    member('u1', 'JDU', 'eleve'),
    member('ins', 'INS', 'instructeur'),
    member('lac', 'LAC', 'lache_toute_mission'),
  ]
  ..aircraft = [
    Aircraft.fromMap('a1', {'registration': 'F-JABC', 'label': 'ULM 1', 'active': true}),
  ];

String preview(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(const Key('preview')), matching: find.byType(Text)))
    .map((t) => t.data)
    .join('\n');

Future<void> pickAircraft(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('f-aircraft')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('ULM 1 (F-JABC)').last);
  await tester.pumpAndSettle();
}

Future<void> addMember(WidgetTester tester, String uid) async {
  await tester.tap(find.text('Ajouter un équipier'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('pick-$uid')));
  await tester.pumpAndSettle();
}

Future<void> saveAndConfirm(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Enregistrer'));
  await tester.pumpAndSettle();
  if (find.text('Confirmer').evaluate().isNotEmpty) {
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('élève : soi-même en premier, fin = départ + 1 h, demande à l\'instructeur', (tester) async {
    final a = api();
    await tester.pumpWidget(host(a, testUser(uid: 'u1')));
    await tester.pumpAndSettle();
    expect(find.text('09:00'), findsOneWidget); // départ : heure pleine suivante
    expect(find.text('10:00'), findsOneWidget); // fin par défaut
    expect(find.byKey(const Key('payer')), findsOneWidget);
    expect(find.text('Payeur : JDU'), findsWidgets);

    await addMember(tester, 'ins');
    await pickAircraft(tester);
    await tester.enterText(find.byKey(const Key('f-destination')), 'Lomé');
    await tester.pumpAndSettle();
    expect(preview(tester), contains('Sera une demande à INS'));

    await saveAndConfirm(tester);
    expect(a.created.single['crew'], ['u1', 'ins']);
    expect(a.created.single['destination'], 'Lomé');
    expect(a.created.single['end'] - a.created.single['start'], 3600000);
    expect(a.created.single.containsKey('pricingMode'), isFalse);
  });

  testWidgets('élève seul : aperçu « impossible » et aucun appel', (tester) async {
    final a = api();
    await tester.pumpWidget(host(a, testUser(uid: 'u1')));
    await tester.pumpAndSettle();
    expect(preview(tester), contains('Impossible : Un élève ne peut voler qu\'avec un instructeur.'));
    await pickAircraft(tester);
    await tester.enterText(find.byKey(const Key('f-destination')), 'Lomé');
    await saveAndConfirm(tester);
    expect(a.created, isEmpty);
    expect(find.text('Un élève ne peut voler qu\'avec un instructeur.'), findsOneWidget);
  });

  testWidgets('ordre modifiable : le payeur change', (tester) async {
    await tester.pumpWidget(host(api(), testUser(uid: 'u1', profile: 'lache_toute_mission')));
    await tester.pumpAndSettle();
    await addMember(tester, 'lac');
    expect(find.text('Payeur : JDU'), findsWidgets);
    await tester.tap(find.byTooltip('Mettre en premier'));
    await tester.pumpAndSettle();
    expect(find.text('Payeur : LAC'), findsWidgets);
  });

  testWidgets('passager sans compte : ajouté, jamais payeur', (tester) async {
    final a = api();
    await tester.pumpWidget(host(a, testUser(uid: 'u1', profile: 'lache_toute_mission')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un passager sans compte'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('passenger-name')), 'Paul');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Paul'), findsOneWidget);
    expect(find.text('Payeur : JDU'), findsWidgets);
    expect(find.text('Ajouter un équipier'), findsNothing); // 2 à bord
  });

  testWidgets('conflit signalé dans l\'aperçu', (tester) async {
    final a = api()
      ..flights = [
        testFlight(id: 'o', start: DateTime(2026, 10, 12, 9, 30), crew: ['lac'], aircraft: 'F-JABC'),
      ];
    await tester.pumpWidget(host(a, testUser(uid: 'u1', profile: 'lache_toute_mission')));
    await tester.pumpAndSettle();
    await pickAircraft(tester);
    expect(preview(tester), contains('Conflit avec le vol du lundi 12 octobre, 09:30–10:30, F-JABC, LAC.'));
  });

  testWidgets('carburant seulement : proposé à un instructeur GAP pour un vol entre GAP', (tester) async {
    final a = api()..categories = {'u1': UserCategory.gap, 'lac': UserCategory.gap};
    await tester.pumpWidget(
        host(a, testUser(uid: 'u1', profile: 'instructeur', category: 'GAP')));
    await tester.pumpAndSettle();
    await addMember(tester, 'lac');
    expect(find.byKey(const Key('f-fuel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('f-fuel')));
    await tester.pumpAndSettle();
    // Le formulaire dépasse la surface de test (800×600) une fois l'équipier
    // et le choix de carburant affichés : l'aperçu n'est alors pas encore
    // matérialisé (ListView à défilement). Le faire défiler dans la vue
    // avant de le lire (cf. Step 3 du brief).
    await tester.scrollUntilVisible(find.byKey(const Key('preview')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(preview(tester), contains('Mode : Carburant seulement'));

    a.categories = {'u1': UserCategory.gap, 'lac': UserCategory.ext};
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
        host(a, testUser(uid: 'u1', profile: 'instructeur', category: 'GAP')));
    await tester.pumpAndSettle();
    await addMember(tester, 'lac');
    expect(find.byKey(const Key('f-fuel')), findsNothing);
  });

  testWidgets('erreur serveur de conflit : message formaté en heure locale', (tester) async {
    final a = api()
      ..failWith = FlightConflict(
        'Conflit avec un autre vol validé.',
        ConflictInfo(
          start: DateTime(2026, 10, 12, 9),
          end: DateTime(2026, 10, 12, 10),
          aircraft: 'F-JABC',
          crew: const ['ins'],
          passengers: const [],
        ),
      );
    await tester.pumpWidget(host(a, testUser(uid: 'u1', profile: 'instructeur')));
    await tester.pumpAndSettle();
    await pickAircraft(tester);
    await tester.enterText(find.byKey(const Key('f-destination')), 'Lomé');
    await saveAndConfirm(tester);
    expect(find.text('Conflit avec le vol du lundi 12 octobre, 09:00–10:00, F-JABC, INS.'),
        findsOneWidget);
  });

  testWidgets('validation : équipage figé, appel validate avec les horaires', (tester) async {
    final a = api();
    final f = testFlight(
        id: 'd', start: DateTime(2026, 10, 13, 9), status: 'demande',
        crew: ['u1', 'ins'], instructorUid: 'ins');
    await tester.pumpWidget(host(a, testUser(uid: 'ins', profile: 'instructeur', shortName: 'INS'),
        flight: f, mode: FlightFormMode.validate));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un équipier'), findsNothing);
    expect(preview(tester), contains('Sera validé'));
    await saveAndConfirm(tester);
    expect(a.validated['d']!['start'], DateTime(2026, 10, 13, 9).millisecondsSinceEpoch);
    expect(a.validated['d']!['destination'], 'Lomé');
  });

  testWidgets(
      'modification : vol commencé la veille, ouverture du sélecteur de date sans exception',
      (tester) async {
    final a = api();
    final f = testFlight(id: 'e', start: DateTime(2026, 10, 11, 9), crew: ['u1']);
    await tester.pumpWidget(
        host(a, testUser(uid: 'u1'), flight: f, mode: FlightFormMode.edit));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    // L'app ne configure pas de localisation FR pour les dialogues Material
    // standard (DatePickerDialog) : le bouton est donc « Cancel », pas
    // « Annuler ».
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('durée prévue maximale dépassée : refusé localement, aucun appel', (tester) async {
    final a = api();
    final start = DateTime(2026, 10, 13, 9);
    final f = testFlight(id: 'e', start: start, end: start.add(const Duration(hours: 13)), crew: ['u1']);
    await tester.pumpWidget(
        host(a, testUser(uid: 'u1'), flight: f, mode: FlightFormMode.edit));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Durée prévue maximale : 12 h.'), findsOneWidget);
    expect(a.updated, isEmpty);
  });

  testWidgets('erreur inattendue à l\'enregistrement : message générique, saisie réactivée',
      (tester) async {
    final a = api()..failWith = Exception('boom');
    await tester.pumpWidget(host(a, testUser(uid: 'u1', profile: 'instructeur')));
    await tester.pumpAndSettle();
    await pickAircraft(tester);
    await tester.enterText(find.byKey(const Key('f-destination')), 'Lomé');
    await saveAndConfirm(tester);
    expect(find.text('Enregistrement impossible. Réessayez.'), findsOneWidget);
    final button = tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(Icons.check), matching: find.byType(IconButton)));
    expect(button.onPressed, isNotNull);
  });
}
