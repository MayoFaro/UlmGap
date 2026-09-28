import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/profiles.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/flight.dart';
import 'package:ulmgap/data/flight_api.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/flight/flight_screen.dart';

import '../../support/fakes.dart';

final now = DateTime(2026, 10, 12, 8, 20);

Widget host(FakeFlightApi api, AppUser me, {Flight? flight}) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      flights: api,
      child: MaterialApp(home: FlightScreen(me: me, flight: flight, now: () => now)),
    );

/// Héberge l'écran derrière un planning minimal, pour vérifier qu'une action
/// referme l'écran et ramène au planning (brief Task 3, Step 1).
Widget pushHost(FakeFlightApi api, AppUser me, {Flight? flight}) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      flights: api,
      child: MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: const Text('planning'),
            floatingActionButton: FloatingActionButton(
              onPressed: () => Navigator.push(
                c,
                MaterialPageRoute(
                    builder: (_) => FlightScreen(me: me, flight: flight, now: () => now)),
              ),
            ),
          ),
        ),
      ),
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

/// Le contenu (fiche + champs + aperçu) dépasse la fenêtre de test par
/// défaut (800x600 logique), comme pour l'ancien écran de détail.
void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

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

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.text('Enregistrer'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('création : appareil présélectionné dès que la liste arrive', (tester) async {
    _useTallView(tester);
    await tester.pumpWidget(host(api(), testUser(uid: 'u1', profile: 'instructeur')));
    await tester.pumpAndSettle();
    expect(find.text('ULM 1 (F-JABC)'), findsOneWidget);
  });

  testWidgets('élève : soi-même en premier, fin = départ + 1 h, demande à l\'instructeur',
      (tester) async {
    _useTallView(tester);
    final a = api();
    await tester.pumpWidget(host(a, testUser(uid: 'u1')));
    await tester.pumpAndSettle();
    expect(find.text('09:00'), findsOneWidget); // départ : heure pleine suivante
    expect(find.text('10:00'), findsOneWidget); // fin par défaut
    expect(find.byKey(const Key('payer')), findsOneWidget);
    expect(find.text('Compte débité : JDU'), findsWidgets);

    await addMember(tester, 'ins');
    await pickAircraft(tester);
    await tester.enterText(find.byKey(const Key('f-destination')), 'Lomé');
    await tester.pumpAndSettle();
    expect(preview(tester), contains('Sera une demande à INS'));

    await save(tester);
    expect(a.created.single['crew'], ['u1', 'ins']);
    expect(a.created.single['destination'], 'Lomé');
    expect(a.created.single['end'] - a.created.single['start'], 3600000);
    expect(a.created.single.containsKey('pricingMode'), isFalse);
  });

  testWidgets('élève seul : aperçu « impossible » et aucun appel', (tester) async {
    _useTallView(tester);
    final a = api();
    await tester.pumpWidget(host(a, testUser(uid: 'u1')));
    await tester.pumpAndSettle();
    expect(
        preview(tester),
        contains(
            'Impossible : Impossible de créer un vol à votre profit sans la présence d\'un instructeur.'));
    await pickAircraft(tester);
    await tester.enterText(find.byKey(const Key('f-destination')), 'Lomé');
    await save(tester);
    expect(a.created, isEmpty);
    expect(find.text('Impossible de créer un vol à votre profit sans la présence d\'un instructeur.'),
        findsOneWidget);
  });

  testWidgets('ordre modifiable par un instructeur : le compte débité change', (tester) async {
    _useTallView(tester);
    await tester.pumpWidget(host(api(), testUser(uid: 'u1', profile: 'instructeur')));
    await tester.pumpAndSettle();
    await addMember(tester, 'lac');
    expect(find.text('Compte débité : JDU'), findsWidgets);
    await tester.tap(find.byTooltip('Mettre en premier'));
    await tester.pumpAndSettle();
    expect(find.text('Compte débité : LAC'), findsWidgets);
  });

  testWidgets('mettre en premier : absent pour un élève, présent pour un instructeur',
      (tester) async {
    _useTallView(tester);
    await tester.pumpWidget(host(api(), testUser(uid: 'u1', profile: 'eleve')));
    await tester.pumpAndSettle();
    await addMember(tester, 'ins');
    expect(find.byTooltip('Mettre en premier'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host(api(), testUser(uid: 'ins', profile: 'instructeur')));
    await tester.pumpAndSettle();
    await addMember(tester, 'u1');
    expect(find.byTooltip('Mettre en premier'), findsOneWidget);
  });

  testWidgets('passager sans compte : ajouté, jamais compte débité', (tester) async {
    _useTallView(tester);
    final a = api();
    await tester.pumpWidget(host(a, testUser(uid: 'u1', profile: 'lache_toute_mission')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un passager sans compte'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('passenger-name')), 'Paul');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Paul'), findsOneWidget);
    expect(find.text('Compte débité : JDU'), findsWidgets);
    expect(find.text('Ajouter un équipier'), findsNothing); // 2 à bord
  });

  testWidgets('conflit signalé dans l\'aperçu', (tester) async {
    _useTallView(tester);
    final a = api()
      ..flights = [
        testFlight(id: 'o', start: DateTime(2026, 10, 12, 9, 30), crew: ['lac'], aircraft: 'F-JABC'),
      ];
    await tester.pumpWidget(host(a, testUser(uid: 'u1', profile: 'lache_toute_mission')));
    await tester.pumpAndSettle();
    await pickAircraft(tester);
    expect(
        preview(tester),
        contains(
            'Conflit : F-JABC est déjà réservé sur le vol du lundi 12 octobre, 09:30–10:30 (LAC).'));
  });

  testWidgets('carburant seulement : proposé à un instructeur GAP pour un vol entre GAP',
      (tester) async {
    _useTallView(tester);
    final a = api()..categories = {'u1': UserCategory.gap, 'lac': UserCategory.gap};
    await tester.pumpWidget(
        host(a, testUser(uid: 'u1', profile: 'instructeur', category: 'GAP')));
    await tester.pumpAndSettle();
    await addMember(tester, 'lac');
    expect(find.byKey(const Key('f-fuel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('f-fuel')));
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
    _useTallView(tester);
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
    await save(tester);
    expect(find.text('Conflit : F-JABC est déjà réservé sur le vol du lundi 12 octobre, 09:00–10:00 (INS).'),
        findsOneWidget);
  });

  testWidgets('édition : ouverture du sélecteur de date sans exception', (tester) async {
    _useTallView(tester);
    final a = api();
    final f = testFlight(id: 'e', start: DateTime(2026, 10, 13, 9), crew: ['u1']);
    await tester.pumpWidget(host(a, testUser(uid: 'u1'), flight: f));
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

  testWidgets('vol clos (départ passé) : champ date inerte, aucune exception', (tester) async {
    _useTallView(tester);
    final a = api();
    final f = testFlight(id: 'e', start: DateTime(2026, 10, 11, 9), crew: ['u1']);
    await tester.pumpWidget(host(a, testUser(uid: 'u1'), flight: f));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsNothing);
  });

  testWidgets('durée prévue maximale dépassée : refusé localement, aucun appel', (tester) async {
    _useTallView(tester);
    final a = api();
    final start = DateTime(2026, 10, 13, 9);
    final f = testFlight(id: 'e', start: start, end: start.add(const Duration(hours: 13)), crew: ['u1']);
    await tester.pumpWidget(host(a, testUser(uid: 'u1'), flight: f));
    await tester.pumpAndSettle();
    await save(tester);
    expect(find.text('Durée prévue maximale : 12 h.'), findsOneWidget);
    expect(a.updated, isEmpty);
  });

  testWidgets('erreur inattendue à l\'enregistrement : message générique, saisie réactivée',
      (tester) async {
    _useTallView(tester);
    final a = api()..failWith = Exception('boom');
    await tester.pumpWidget(host(a, testUser(uid: 'u1', profile: 'instructeur')));
    await tester.pumpAndSettle();
    await pickAircraft(tester);
    await tester.enterText(find.byKey(const Key('f-destination')), 'Lomé');
    await save(tester);
    expect(find.text('Enregistrement impossible. Réessayez.'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Enregistrer'));
    expect(button.onPressed, isNotNull);
  });

  // --- Vol existant : fiche, droits, actions en bas ---

  testWidgets('informations, compte débité et tarification', (tester) async {
    _useTallView(tester);
    final f = testFlight(
        id: 'd', start: DateTime(2026, 10, 13, 9), status: 'demande',
        crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins');
    await tester.pumpWidget(host(api(), testUser(uid: 'u1'), flight: f));
    await tester.pumpAndSettle();
    expect(find.text('mardi 13 octobre'), findsWidgets); // titre + champ Date
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('ULM 1 (F-JABC)'), findsOneWidget);
    expect(find.text('Lomé'), findsOneWidget);
    expect(find.text('Demande'), findsOneWidget);
    expect(find.text('Compte débité'), findsOneWidget);
    expect(find.text('Instructeur désigné : INS'), findsOneWidget);
    expect(find.text('Tarification'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
  });

  testWidgets('instructeur désigné sur une demande : Valider et Refuser, pas Enregistrer',
      (tester) async {
    _useTallView(tester);
    final a = api();
    final f = testFlight(
        id: 'd', start: DateTime(2026, 10, 13, 9), status: 'demande',
        crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins');
    await tester.pumpWidget(pushHost(a, testUser(uid: 'ins', profile: 'instructeur', shortName: 'INS'),
        flight: f));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Valider'), findsOneWidget);
    expect(find.text('Refuser'), findsOneWidget);
    expect(find.text('Enregistrer'), findsNothing);
    expect(find.text('Ajouter un équipier'), findsNothing); // équipage figé

    await tester.enterText(find.byKey(const Key('f-destination')), 'Cotonou');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(a.validated['d']!['destination'], 'Cotonou');
    expect(find.text('planning'), findsOneWidget);
    expect(find.byType(FlightScreen), findsNothing);
  });

  testWidgets('créateur d\'une demande : Enregistrer et Annuler le vol, pas Valider',
      (tester) async {
    _useTallView(tester);
    final a = api();
    final f = testFlight(
        id: 'd', start: DateTime(2026, 10, 13, 9), status: 'demande',
        crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins');
    await tester.pumpWidget(pushHost(a, testUser(uid: 'u1'), flight: f));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Enregistrer'), findsOneWidget);
    expect(find.text('Annuler le vol'), findsOneWidget);
    expect(find.text('Valider'), findsNothing);

    await tester.tap(find.text('Annuler le vol'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oui, annuler'));
    await tester.pumpAndSettle();
    expect(a.cancelled, ['d']);
    expect(find.text('planning'), findsOneWidget);
    expect(find.byType(FlightScreen), findsNothing);
  });

  testWidgets('refus avec motif par l\'instructeur désigné', (tester) async {
    _useTallView(tester);
    final a = api();
    final f = testFlight(
        id: 'd', start: DateTime(2026, 10, 13, 9), status: 'demande',
        crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins');
    await tester.pumpWidget(
        pushHost(a, testUser(uid: 'ins', profile: 'instructeur'), flight: f));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refuser'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('refuse-reason')), 'Météo');
    await tester.tap(find.text('Refuser').last);
    await tester.pumpAndSettle();
    expect(a.refused['d'], 'Météo');
    expect(find.text('planning'), findsOneWidget);
    expect(find.byType(FlightScreen), findsNothing);
  });

  testWidgets('utilisateur sans droit : aucun bouton, champs inertes', (tester) async {
    _useTallView(tester);
    final f = testFlight(
        id: 'v', start: DateTime(2026, 10, 13, 9), status: 'valide',
        crew: ['ins'], createdBy: 'ins');
    await tester.pumpWidget(host(api(), testUser(uid: 'u1'), flight: f));
    await tester.pumpAndSettle();
    expect(find.text('Enregistrer'), findsNothing);
    expect(find.text('Valider'), findsNothing);
    expect(find.text('Refuser'), findsNothing);
    expect(find.text('Annuler le vol'), findsNothing);
    await tester.tap(find.byKey(const Key('f-aircraft')));
    await tester.pumpAndSettle();
    expect(find.text('ULM 1 (F-JABC)'), findsOneWidget); // toujours affiché, mais liste non ouverte
  });

  testWidgets('demande expirée : « Refusé (non validée avant le départ) », aucun bouton',
      (tester) async {
    _useTallView(tester);
    final f = testFlight(
        id: 'old', start: DateTime(2026, 10, 12, 7), status: 'demande',
        crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins');
    await tester.pumpWidget(host(api(), testUser(uid: 'ins', profile: 'instructeur'), flight: f));
    await tester.pumpAndSettle();
    expect(find.text('Refusé (non validée avant le départ)'), findsOneWidget);
    expect(find.text('Valider'), findsNothing);
    expect(find.text('Refuser'), findsNothing);
  });
}
