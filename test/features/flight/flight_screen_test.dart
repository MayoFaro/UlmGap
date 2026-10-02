import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/money.dart';
import 'package:ulmgap/core/pricing.dart';
import 'package:ulmgap/core/profiles.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/finance_api.dart';
import 'package:ulmgap/data/flight.dart';
import 'package:ulmgap/data/flight_api.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/flight/flight_screen.dart';
import 'package:ulmgap/features/flight/flight_texts.dart' show uncertainMessage;

import '../../support/fakes.dart';

final now = DateTime(2026, 10, 12, 8, 20);

/// Un vol existant passé à l'écran doit aussi être « connu » du serveur
/// simulé (watchFlight le sert depuis `api.flights`, Task 3 retours de
/// recette) : sinon la première émission du flux (introuvable) écraserait
/// aussitôt l'état initial et l'écran afficherait « Vol introuvable. ».
void _seedFlight(FakeFlightApi api, Flight? flight) {
  if (flight != null && !api.flights.any((f) => f.id == flight.id)) {
    api.flights = [...api.flights, flight];
  }
}

Widget host(FakeFlightApi api, AppUser me, {Flight? flight, FinanceApi? finance}) {
  _seedFlight(api, flight);
  return AppServices(
    auth: FakeAuthService(),
    users: FakeUserRepository(),
    flights: api,
    finance: finance,
    child: MaterialApp(home: FlightScreen(me: me, flight: flight, now: () => now)),
  );
}

/// Héberge l'écran derrière un planning minimal, pour vérifier qu'une action
/// referme l'écran et ramène au planning (brief Task 3, Step 1).
Widget pushHost(FakeFlightApi api, AppUser me, {Flight? flight, FinanceApi? finance}) {
  _seedFlight(api, flight);
  return AppServices(
    auth: FakeAuthService(),
    users: FakeUserRepository(),
    flights: api,
    finance: finance,
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
}

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

/// Code court de l'équipier marqué « Compte débité » (mention unique).
void expectDebited(String short) {
  expect(find.text('Compte débité'), findsOneWidget);
  expect(find.textContaining('Compte débité :'), findsNothing);
  expect(
    find.descendant(
      of: find.ancestor(of: find.text('Compte débité'), matching: find.byType(ListTile)),
      matching: find.text(short),
    ),
    findsOneWidget,
  );
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
    expect(find.byKey(const Key('payer')), findsNothing);
    expectDebited('JDU');

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
    expectDebited('JDU');
    await tester.tap(find.byTooltip('Mettre en premier'));
    await tester.pumpAndSettle();
    expectDebited('LAC');
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

  testWidgets(
      'retirer : un instructeur peut se retirer lui-même du vol qu\'il crée',
      (tester) async {
    _useTallView(tester);
    final a = api();
    await tester
        .pumpWidget(host(a, testUser(uid: 'ins', profile: 'instructeur', shortName: 'INS')));
    await tester.pumpAndSettle();
    await addMember(tester, 'lac');
    expect(find.text('INS'), findsWidgets);
    // Deux lignes affichent « Retirer » (instructeur : droit élargi à sa
    // propre ligne) ; la première est celle de l'instructeur lui-même.
    expect(find.byTooltip('Retirer'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Retirer').first);
    await tester.pumpAndSettle();
    expect(find.text('INS'), findsNothing); // sa ligne a disparu

    await pickAircraft(tester);
    await tester.enterText(find.byKey(const Key('f-destination')), 'Lomé');
    await save(tester);
    expect(a.created.single['crew'], ['lac']); // l'équipage envoyé ne le contient plus
  });

  testWidgets('retirer : absent sur sa propre ligne pour un lâché (ni instructeur ni admin)',
      (tester) async {
    _useTallView(tester);
    await tester.pumpWidget(host(api(), testUser(uid: 'u1', profile: 'lache_toute_mission')));
    await tester.pumpAndSettle();
    await addMember(tester, 'ins');
    // Une seule ligne affiche « Retirer » : celle de l'équipier ajouté, pas
    // la sienne (spec §1 du context.md : hors instructeur/admin, le créateur
    // reste obligatoirement le compte débité en première position).
    expect(find.byTooltip('Retirer'), findsOneWidget);
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
    expectDebited('JDU');
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
    expect(find.text(uncertainMessage), findsOneWidget);
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
    expect(find.text('Enregistrer'), findsNothing);
    expect(find.text('Annuler le vol'), findsNothing);
  });

  // --- Fix 1 (retours de recette) : aperçu du mode de tarification en édition ---

  testWidgets(
      'non-instructeur : retirer le passager d\'un vol GAP en carburant seulement '
      '→ aperçu Standard', (tester) async {
    _useTallView(tester);
    final f = testFlight(
        id: 'e', start: DateTime(2026, 10, 13, 9), crew: ['u1'],
        passengers: const ['Paul'], pricingMode: 'fuel_only', createdBy: 'u1');
    await tester.pumpWidget(host(
        api(), testUser(uid: 'u1', profile: 'lache_toute_mission', category: 'GAP'), flight: f));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Retirer le passager'));
    await tester.pumpAndSettle();
    expect(preview(tester), contains('Mode : Standard'));
  });

  testWidgets(
      'non-instructeur : mode carburant seulement conservé quand seule la destination '
      'change (équipage et passager inchangés)', (tester) async {
    _useTallView(tester);
    final f = testFlight(
        id: 'e', start: DateTime(2026, 10, 13, 9), crew: ['u1', 'lac'],
        pricingMode: 'fuel_only', createdBy: 'u1');
    await tester.pumpWidget(
        host(api(), testUser(uid: 'u1', profile: 'lache_toute_mission'), flight: f));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('f-destination')), 'Cotonou');
    await tester.pumpAndSettle();
    expect(preview(tester), contains('Mode : Carburant seulement'));
  });

  // --- Fix 3 (retours de recette) : reflet des changements serveur en direct ---

  testWidgets(
      'mise à jour en direct : une demande validée ailleurs fait disparaître Valider',
      (tester) async {
    _useTallView(tester);
    final a = api();
    final f = testFlight(
        id: 'd', start: DateTime(2026, 10, 13, 9), status: 'demande',
        crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins');
    a.flights = [f];
    await tester.pumpWidget(
        host(a, testUser(uid: 'ins', profile: 'instructeur', shortName: 'INS'), flight: f));
    await tester.pumpAndSettle();
    expect(find.text('Valider'), findsOneWidget);
    expect(find.text('Demande'), findsOneWidget);

    a.flightsCtrl.add([testFlight(
        id: 'd', start: DateTime(2026, 10, 13, 9), status: 'valide',
        crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins')]);
    await tester.pumpAndSettle();
    expect(find.text('Valider'), findsNothing);
    expect(find.text('Validé'), findsOneWidget);
  });

  testWidgets('mise à jour en direct : vol supprimé pendant la consultation → Vol introuvable',
      (tester) async {
    _useTallView(tester);
    final a = api();
    final f = testFlight(id: 'd', start: DateTime(2026, 10, 13, 9), crew: ['u1']);
    a.flights = [f];
    await tester.pumpWidget(host(a, testUser(uid: 'u1'), flight: f));
    await tester.pumpAndSettle();
    expect(find.text('Enregistrer'), findsOneWidget);

    a.flightsCtrl.add([testFlight(
        id: 'd', start: DateTime(2026, 10, 13, 9), crew: ['u1'], deleted: true)]);
    await tester.pumpAndSettle();
    expect(find.text('Vol introuvable.'), findsOneWidget);
    expect(find.text('Enregistrer'), findsNothing);
  });

  // --- Fix 4 (retours de recette) : Enregistrer ramène au planning ---

  testWidgets('édition réussie : Enregistrer appelle api.update et revient au planning',
      (tester) async {
    _useTallView(tester);
    final a = api();
    final f = testFlight(id: 'e', start: DateTime(2026, 10, 13, 9), crew: ['u1']);
    await tester.pumpWidget(
        pushHost(a, testUser(uid: 'u1', profile: 'lache_toute_mission'), flight: f));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('f-destination')), 'Cotonou');
    await save(tester);
    expect(a.updated['e']!['destination'], 'Cotonou');
    expect(find.text('planning'), findsOneWidget);
    expect(find.byType(FlightScreen), findsNothing);
  });

  testWidgets('création réussie : Enregistrer appelle api.create et revient au planning',
      (tester) async {
    _useTallView(tester);
    final a = api();
    await tester.pumpWidget(pushHost(a, testUser(uid: 'u1', profile: 'instructeur')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await pickAircraft(tester);
    await tester.enterText(find.byKey(const Key('f-destination')), 'Lomé');
    await save(tester);
    expect(a.created.single['destination'], 'Lomé');
    expect(find.text('planning'), findsOneWidget);
    expect(find.byType(FlightScreen), findsNothing);
    // Confirmation affichée sur le planning : le serveur a enregistré le vol.
    expect(find.text('Vol enregistré.'), findsOneWidget);
  });

  // --- Task 9 (finances) : coût estimé, crédit disponible, clôture ---

  testWidgets('aperçu : coût estimé EXT 60 min = 70 000 FCFA', (tester) async {
    _useTallView(tester);
    final finance = FakeFinanceApi();
    await tester.pumpWidget(host(
        api(), testUser(uid: 'u1', profile: 'instructeur', category: 'EXT', balance: 100000),
        finance: finance));
    await tester.pumpAndSettle();
    await pickAircraft(tester);
    expect(preview(tester), contains('Coût estimé : ${formatFcfa(70000)}'));
  });

  testWidgets('aperçu : crédit insuffisant → message, aucun appel à l\'enregistrement',
      (tester) async {
    _useTallView(tester);
    final a = api();
    final finance = FakeFinanceApi();
    await tester.pumpWidget(host(
        a, testUser(uid: 'u1', profile: 'instructeur', category: 'EXT', balance: 50000),
        finance: finance));
    await tester.pumpAndSettle();
    await pickAircraft(tester);
    await tester.enterText(find.byKey(const Key('f-destination')), 'Lomé');
    await tester.pumpAndSettle();
    final expected = 'Crédit insuffisant : il manque ${formatFcfa(20000)}.';
    expect(preview(tester), contains(expected));
    await save(tester);
    expect(a.created, isEmpty);
    expect(find.text(expected), findsWidgets);
  });

  testWidgets('aperçu : crédit masqué pour un élève qui voit le vol d\'un autre compte',
      (tester) async {
    _useTallView(tester);
    final f = testFlight(
        id: 'other', start: DateTime(2026, 10, 13, 9), crew: ['lac'], createdBy: 'lac');
    final finance = FakeFinanceApi();
    await tester.pumpWidget(
        host(api(), testUser(uid: 'u1', profile: 'eleve'), flight: f, finance: finance));
    await tester.pumpAndSettle();
    expect(find.textContaining('Crédit disponible'), findsNothing);
  });

  testWidgets(
      'clôture : 90 min GAP → aperçu 15 000 FCFA, closeFlight(actualMinutes: 90) puis retour '
      'au planning', (tester) async {
    _useTallView(tester);
    final start = DateTime(2026, 10, 12, 5);
    final f = testFlight(
        id: 'c1', start: start, end: start.add(const Duration(minutes: 90)),
        crew: ['u1'], createdBy: 'u1', status: 'valide');
    final finance = FakeFinanceApi();
    await tester.pumpWidget(
        pushHost(api(), testUser(uid: 'u1', category: 'GAP'), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Clôturer'), findsOneWidget);
    await tester.tap(find.text('Clôturer'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('closing-minutes')), findsOneWidget);
    expect(find.text('Montant : ${formatFcfa(15000)}'), findsOneWidget);
    await tester.tap(find.text('Clôturer').last);
    await tester.pumpAndSettle();
    expect(finance.closed.single['flightId'], 'c1');
    expect(finance.closed.single['actualMinutes'], 90);
    expect(finance.closed.single['shortFlightAmount'], isNull);
    expect(finance.closed.single['customAmount'], isNull);
    expect(finance.closed.single['landings'], 1);
    expect(finance.closed.single['waterLandings'], 0);
    expect(find.text('planning'), findsOneWidget);
    expect(find.byType(FlightScreen), findsNothing);
  });

  testWidgets(
      'clôture : équipier non-staff, compte débité autre (catégorie inconnue) → '
      'clôture quand même possible (fix round 1, décision 2)', (tester) async {
    _useTallView(tester);
    final a = api();
    a.directory = [...a.directory, member('pay', 'PAY', 'eleve')];
    final start = DateTime(2026, 10, 12, 5);
    final f = testFlight(
        id: 'c5', start: start, end: start.add(const Duration(minutes: 90)),
        crew: ['pay', 'u1'], createdBy: 'pay', status: 'valide');
    final finance = FakeFinanceApi();
    // 'u1' est équipier, pas staff, et n'est pas le compte débité ('pay') :
    // watchCategories n'est pas écouté (_mayChoose == false), donc la
    // catégorie de 'pay' est inconnue ici.
    await tester
        .pumpWidget(pushHost(a, testUser(uid: 'u1', profile: 'eleve'), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Clôturer'), findsOneWidget);
    await tester.tap(find.text('Clôturer'));
    await tester.pumpAndSettle();
    // Aucun aperçu chiffré local (catégorie inconnue), mais le formulaire
    // reste utilisable.
    expect(find.text('Montant calculé par le serveur à la clôture.'), findsOneWidget);
    expect(find.textContaining('Montant :'), findsNothing);
    await tester.tap(find.text('Clôturer').last);
    await tester.pumpAndSettle();
    expect(finance.closed.single['flightId'], 'c5');
    expect(finance.closed.single['actualMinutes'], 90);
    expect(find.text('planning'), findsOneWidget);
    expect(find.byType(FlightScreen), findsNothing);
  });

  testWidgets(
      'clôture par un élève (sa décision serait « demande ») : tarifs figés du vol, pas les '
      'tarifs courants', (tester) async {
    _useTallView(tester);
    final start = DateTime(2026, 10, 12, 5);
    // Figé à 45 min au moment de la validation ; abaissé depuis à 30 min.
    final f = testFlight(
        id: 'c6', start: start, end: start.add(const Duration(hours: 1)),
        crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins', status: 'valide',
        pricingSnapshot: defaultPricing.toMap());
    final finance = FakeFinanceApi()
      ..pricing = Pricing.fromMap({...defaultPricing.toMap(), 'minPlannedMinutes': 30});
    await tester.pumpWidget(pushHost(api(), testUser(uid: 'u1', profile: 'eleve', category: 'GAP'),
        flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clôturer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('closing-minutes')), '40');
    await tester.pumpAndSettle();
    // 40 min < 45 (snapshot) : le serveur exigera le montant à facturer.
    expect(find.byKey(const Key('closing-short-amount')), findsOneWidget);
  });

  testWidgets('crédit disponible : un vol passé non clôturé du compte débité est déduit',
      (tester) async {
    _useTallView(tester);
    final past = DateTime(2026, 10, 10, 9);
    final finance = FakeFinanceApi()
      ..flights = [
        testFlight(
            id: 'old', start: past, crew: ['u1'], createdBy: 'u1', status: 'valide',
            payerUidField: 'u1'),
      ];
    await tester.pumpWidget(host(
        api(), testUser(uid: 'u1', profile: 'instructeur', category: 'EXT', balance: 100000),
        finance: finance));
    await tester.pumpAndSettle();
    await pickAircraft(tester);
    // 100 000 − 70 000 (vol passé, EXT 60 min) = 30 000.
    expect(preview(tester), contains('Crédit disponible de JDU : ${formatFcfa(30000)}'));
  });

  testWidgets('clôture : vol standard de 30 min → montant à facturer exigé', (tester) async {
    _useTallView(tester);
    final start = DateTime(2026, 10, 12, 5);
    final f = testFlight(
        id: 'c2', start: start, end: start.add(const Duration(hours: 1)),
        crew: ['u1'], createdBy: 'u1', status: 'valide');
    final finance = FakeFinanceApi();
    await tester.pumpWidget(pushHost(api(), testUser(uid: 'u1'), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clôturer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('closing-minutes')), '30');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('closing-short-amount')), findsOneWidget);
    await tester.tap(find.text('Clôturer').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Montant à facturer obligatoire'), findsOneWidget);
    expect(finance.closed, isEmpty);
  });

  testWidgets('clôture : passager sans compte → montant différent envoyé en customAmount',
      (tester) async {
    _useTallView(tester);
    final start = DateTime(2026, 10, 12, 5);
    final f = testFlight(
        id: 'c3', start: start, end: start.add(const Duration(hours: 1)),
        crew: ['u1'], createdBy: 'u1', status: 'valide', passengers: const ['Paul']);
    final finance = FakeFinanceApi();
    await tester.pumpWidget(pushHost(api(), testUser(uid: 'u1'), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clôturer'));
    await tester.pumpAndSettle();
    expect(find.text('Montant différent (facturé hors app)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('closing-custom-check')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('closing-custom-amount')), '5000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clôturer').last);
    await tester.pumpAndSettle();
    expect(finance.closed.single['customAmount'], 5000);
    expect(finance.closed.single['shortFlightAmount'], isNull);
  });

  testWidgets('clôture : montant saisi supérieur à 200 000 → refusé localement', (tester) async {
    _useTallView(tester);
    final start = DateTime(2026, 10, 12, 5);
    final f = testFlight(
        id: 'c4', start: start, end: start.add(const Duration(hours: 1)),
        crew: ['u1'], createdBy: 'u1', status: 'valide');
    final finance = FakeFinanceApi();
    await tester.pumpWidget(pushHost(api(), testUser(uid: 'u1'), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clôturer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('closing-minutes')), '30');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('closing-short-amount')), '250000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clôturer').last);
    await tester.pumpAndSettle();
    expect(find.text('Montant trop élevé (200 000 FCFA au maximum).'), findsOneWidget);
    expect(finance.closed, isEmpty);
  });

  testWidgets('vol clôturé : ligne « Clôturé », aucun bouton pour un non-admin', (tester) async {
    _useTallView(tester);
    final f = testFlight(
        id: 'z', start: DateTime(2026, 10, 12, 5), end: DateTime(2026, 10, 12, 6, 30),
        crew: ['u1'], createdBy: 'u1', status: 'valide', isClosed: true,
        actualFlightMinutes: 90, billedAmount: 15000, billedTo: 'account');
    await tester.pumpWidget(host(api(), testUser(uid: 'u1'), flight: f));
    await tester.pumpAndSettle();
    expect(find.text('Clôturé : 1 h 30, ${formatFcfa(15000)} débité sur le compte de JDU'),
        findsOneWidget);
    expect(find.text('Clôturer'), findsNothing);
    expect(find.text('Enregistrer'), findsNothing);
  });

  // --- Task 10 (plan 3) : correction et suppression admin ---

  testWidgets(
      'admin : correction d\'un vol clôturé → adminUpdateFlight(actualMinutes), aperçu de '
      'régularisation, puis retour au planning', (tester) async {
    _useTallView(tester);
    final a = api();
    a.categories = {'u1': UserCategory.gap};
    final start = DateTime(2026, 10, 12, 5);
    final f = testFlight(
        id: 'ac1', start: start, end: start.add(const Duration(minutes: 90)),
        crew: ['u1'], createdBy: 'u1', status: 'valide', isClosed: true,
        actualFlightMinutes: 90, billedAmount: 15000, billedTo: 'account');
    final finance = FakeFinanceApi();
    await tester.pumpWidget(pushHost(
        a, testUser(uid: 'adm', isAdmin: true, profile: null), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Corriger'), findsOneWidget);
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('correct-minutes')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('correct-minutes')), '120');
    await tester.pumpAndSettle();
    // 120 min GAP standard : 12 000 (forfait) + (120-75) min à 12 000/h = 21 000,
    // contre 15 000 facturés initialement : le compte (inchangé) est
    // remboursé des 15 000 déjà débités puis débité des 21 000 dus, soit un
    // débit supplémentaire net de 6 000 (régularisation négative).
    expect(find.text('Régularisation : ${formatFcfa(-6000)} sur le compte de JDU'),
        findsOneWidget);
    await tester.tap(find.text('Enregistrer la correction'));
    await tester.pumpAndSettle();
    expect(finance.adminUpdated['ac1']!['actualMinutes'], 120);
    // Vol clôturé avant le plan 4b (sans nombres) : pré-rempli à 1 et 0.
    expect(finance.adminUpdated['ac1']!['landings'], 1);
    // Appareil non amphibie, vol sans amerrissages : champ non envoyé.
    expect(finance.adminUpdated['ac1']!.containsKey('waterLandings'), isFalse);
    expect(find.text('planning'), findsOneWidget);
    expect(find.byType(FlightScreen), findsNothing);
  });

  testWidgets(
      'admin : correction sans rien changer → aucune régularisation (même facture, même '
      'compte)', (tester) async {
    _useTallView(tester);
    final a = api();
    a.categories = {'u1': UserCategory.gap};
    final start = DateTime(2026, 10, 12, 5);
    final f = testFlight(
        id: 'ac1b', start: start, end: start.add(const Duration(minutes: 90)),
        crew: ['u1'], createdBy: 'u1', status: 'valide', isClosed: true,
        actualFlightMinutes: 90, billedAmount: 15000, billedTo: 'account');
    await tester.pumpWidget(pushHost(
        a, testUser(uid: 'adm', isAdmin: true, profile: null), flight: f));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    expect(find.text('Aucune régularisation.'), findsOneWidget);
  });

  testWidgets(
      'admin : correction d\'un vol clôturé avec changement de compte débité → deux lignes de '
      'régularisation (remboursement de l\'ancien, débit du nouveau)', (tester) async {
    _useTallView(tester);
    final a = api();
    a.directory = [...a.directory, member('b', 'BBB', 'eleve')];
    a.categories = {'u1': UserCategory.gap, 'b': UserCategory.gap};
    final start = DateTime(2026, 10, 12, 5);
    final f = testFlight(
        id: 'ac2', start: start, end: start.add(const Duration(minutes: 90)),
        crew: ['u1', 'b'], createdBy: 'u1', status: 'valide', isClosed: true,
        actualFlightMinutes: 90, billedAmount: 15000, billedTo: 'account');
    final finance = FakeFinanceApi();
    await tester.pumpWidget(pushHost(
        a, testUser(uid: 'adm', isAdmin: true, profile: null), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    // Mettre B (deuxième de l'équipage) en premier : nouveau compte débité.
    await tester.tap(find.byTooltip('Mettre en premier'));
    await tester.pumpAndSettle();
    expect(find.text('Régularisation : +${formatFcfa(15000)} sur le compte de JDU'),
        findsOneWidget);
    expect(find.text('Régularisation : ${formatFcfa(-15000)} sur le compte de BBB'),
        findsOneWidget);
    await tester.tap(find.text('Enregistrer la correction'));
    await tester.pumpAndSettle();
    expect(finance.adminUpdated['ac2'], isNotNull);
  });

  testWidgets(
      'admin : retirer le passager pendant une correction réinitialise « Montant différent »',
      (tester) async {
    _useTallView(tester);
    final a = api();
    a.categories = {'u1': UserCategory.gap};
    final start = DateTime(2026, 10, 12, 5);
    final f = testFlight(
        id: 'ac3', start: start, end: start.add(const Duration(minutes: 90)),
        crew: ['u1'], createdBy: 'u1', status: 'valide', isClosed: true,
        actualFlightMinutes: 90, billedAmount: 5000, billedTo: 'off_app',
        passengers: const ['Paul']);
    final finance = FakeFinanceApi();
    await tester.pumpWidget(pushHost(
        a, testUser(uid: 'adm', isAdmin: true, profile: null), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('correct-custom-check')), findsOneWidget);
    await tester.tap(find.byTooltip('Retirer le passager'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('correct-custom-check')), findsNothing);
    await tester.tap(find.text('Enregistrer la correction'));
    await tester.pumpAndSettle();
    final payload = finance.adminUpdated['ac3']!;
    expect(payload.containsKey('customAmount'), isFalse);
    expect(payload['pricingMode'], 'standard');
  });

  testWidgets(
      'admin : correction d\'un vol clôturé (branche standard) → payload minimal, sans '
      'pricingMode ni shortFlightAmount/customAmount', (tester) async {
    _useTallView(tester);
    final a = api();
    a.categories = {'u1': UserCategory.ext};
    final start = DateTime(2026, 10, 12, 5);
    final f = testFlight(
        id: 'ac4', start: start, end: start.add(const Duration(minutes: 90)),
        crew: ['u1'], createdBy: 'u1', status: 'valide', isClosed: true,
        actualFlightMinutes: 90, billedAmount: 70000, billedTo: 'account');
    final finance = FakeFinanceApi();
    await tester.pumpWidget(pushHost(
        a, testUser(uid: 'adm', isAdmin: true, profile: null), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    // Catégorie non-GAP : aucun choix de mode proposé, rien n'a changé ici.
    expect(find.byKey(const Key('f-fuel')), findsNothing);
    await tester.tap(find.text('Enregistrer la correction'));
    await tester.pumpAndSettle();
    final payload = finance.adminUpdated['ac4']!;
    expect(payload.containsKey('pricingMode'), isFalse);
    expect(payload.containsKey('shortFlightAmount'), isFalse);
    expect(payload.containsKey('customAmount'), isFalse);
    expect(payload['actualMinutes'], 90);
  });

  testWidgets(
      'admin : correction d\'un vol clôturé (branche montant différent) → customAmount envoyé, '
      'sans pricingMode ni shortFlightAmount', (tester) async {
    _useTallView(tester);
    final a = api();
    a.categories = {'u1': UserCategory.gap};
    final start = DateTime(2026, 10, 12, 5);
    final f = testFlight(
        id: 'ac5', start: start, end: start.add(const Duration(minutes: 90)),
        crew: ['u1'], createdBy: 'u1', status: 'valide', isClosed: true,
        actualFlightMinutes: 90, billedAmount: 15000, billedTo: 'account',
        passengers: const ['Paul']);
    final finance = FakeFinanceApi();
    await tester.pumpWidget(pushHost(
        a, testUser(uid: 'adm', isAdmin: true, profile: null), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('correct-custom-check')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('correct-custom-amount')), '5000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer la correction'));
    await tester.pumpAndSettle();
    final payload = finance.adminUpdated['ac5']!;
    expect(payload['customAmount'], 5000);
    expect(payload.containsKey('pricingMode'), isFalse);
    expect(payload.containsKey('shortFlightAmount'), isFalse);
  });

  testWidgets(
      'admin : suppression confirmée d\'un vol clôturé et débité → adminDeleteFlight avec '
      'mention du remboursement, puis retour au planning', (tester) async {
    _useTallView(tester);
    final f = testFlight(
        id: 'ad1', start: DateTime(2026, 10, 12, 5), end: DateTime(2026, 10, 12, 6, 30),
        crew: ['u1'], createdBy: 'u1', status: 'valide', isClosed: true,
        actualFlightMinutes: 90, billedAmount: 15000, billedTo: 'account');
    final finance = FakeFinanceApi();
    await tester.pumpWidget(pushHost(
        api(), testUser(uid: 'adm', isAdmin: true, profile: null), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer le vol'));
    await tester.pumpAndSettle();
    expect(find.text('Le montant débité sera remboursé.'), findsOneWidget);
    await tester.tap(find.text('Oui, supprimer'));
    await tester.pumpAndSettle();
    expect(finance.adminDeleted, ['ad1']);
    expect(find.text('planning'), findsOneWidget);
    expect(find.byType(FlightScreen), findsNothing);
  });

  testWidgets('admin : suppression d\'un vol non clôturé → pas de mention de remboursement',
      (tester) async {
    _useTallView(tester);
    final f = testFlight(
        id: 'ad2', start: DateTime(2026, 10, 13, 9), crew: ['u1'], createdBy: 'u1',
        status: 'valide');
    final finance = FakeFinanceApi();
    await tester.pumpWidget(pushHost(
        api(), testUser(uid: 'adm', isAdmin: true, profile: null), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer le vol'));
    await tester.pumpAndSettle();
    expect(find.text('Le montant débité sera remboursé.'), findsNothing);
    await tester.tap(find.text('Oui, supprimer'));
    await tester.pumpAndSettle();
    expect(finance.adminDeleted, ['ad2']);
  });

  testWidgets('non-admin : ni Corriger ni Supprimer le vol, même sur un vol clôturé',
      (tester) async {
    _useTallView(tester);
    final f = testFlight(
        id: 'z2', start: DateTime(2026, 10, 12, 5), end: DateTime(2026, 10, 12, 6, 30),
        crew: ['u1'], createdBy: 'u1', status: 'valide', isClosed: true,
        actualFlightMinutes: 90, billedAmount: 15000, billedTo: 'account');
    await tester.pumpWidget(host(api(), testUser(uid: 'u1'), flight: f));
    await tester.pumpAndSettle();
    expect(find.text('Corriger'), findsNothing);
    expect(find.text('Supprimer le vol'), findsNothing);
  });

  // --- plan 4b ---

  testWidgets('clôture sur un appareil amphibie : amerrissages saisis et transmis',
      (tester) async {
    _useTallView(tester);
    final a = api()
      ..aircraft = [
        Aircraft.fromMap('a1',
            {'registration': 'F-JABC', 'label': 'ULM 1', 'active': true, 'amphibious': true}),
      ];
    final start = DateTime(2026, 10, 12, 5);
    final f = testFlight(
        id: 'w1', start: start, end: start.add(const Duration(minutes: 90)),
        crew: ['u1'], createdBy: 'u1', status: 'valide');
    final finance = FakeFinanceApi();
    await tester.pumpWidget(
        pushHost(a, testUser(uid: 'u1', category: 'GAP'), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clôturer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('closing-water-landings')), '2');
    await tester.tap(find.text('Clôturer').last);
    await tester.pumpAndSettle();
    expect(finance.closed.single['landings'], 1);
    expect(finance.closed.single['waterLandings'], 2);
  });

  testWidgets('correction admin : nombres stockés pré-remplis, amerrissages si amphibie',
      (tester) async {
    _useTallView(tester);
    final a = api()
      ..categories = {'u1': UserCategory.gap}
      ..aircraft = [
        Aircraft.fromMap('a1',
            {'registration': 'F-JABC', 'label': 'ULM 1', 'active': true, 'amphibious': true}),
      ];
    final start = DateTime(2026, 10, 12, 5);
    final f = Flight.fromMap('ac9', {
      'start': start, 'end': start.add(const Duration(minutes: 90)), 'destination': 'Lomé',
      'aircraftId': 'a1', 'aircraft': 'F-JABC', 'crew': ['u1'], 'passengers': <String>[],
      'status': 'valide', 'createdBy': 'u1', 'pricingMode': 'standard', 'isClosed': true,
      'deleted': false, 'actualFlightMinutes': 90, 'billedAmount': 15000, 'billedTo': 'account',
      'landings': 3, 'waterLandings': 2,
    });
    final finance = FakeFinanceApi();
    await tester.pumpWidget(pushHost(
        a, testUser(uid: 'adm', isAdmin: true, profile: null), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 att., 2 am.'), findsOneWidget);
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('correct-landings'))).controller!.text, '3');
    await tester.enterText(find.byKey(const Key('correct-water-landings')), '4');
    await tester.tap(find.text('Enregistrer la correction'));
    await tester.pumpAndSettle();
    expect(finance.adminUpdated['ac9']!['landings'], 3);
    expect(finance.adminUpdated['ac9']!['waterLandings'], 4);
  });

  // --- plan 4b, revue finale : appareil amphibie inactif ---

  Flight closedOn(String id, String aircraftId, {int landings = 0, int water = 2}) =>
      Flight.fromMap(id, {
        'start': DateTime(2026, 10, 12, 5), 'end': DateTime(2026, 10, 12, 6, 30),
        'destination': 'Lomé', 'aircraftId': aircraftId, 'aircraft': 'F-JAMP', 'crew': ['u1'],
        'passengers': <String>[], 'status': 'valide', 'createdBy': 'u1', 'pricingMode': 'standard',
        'isClosed': true, 'deleted': false, 'actualFlightMinutes': 90, 'billedAmount': 15000,
        'billedTo': 'account', 'landings': landings, 'waterLandings': water,
      });

  Future<FakeFinanceApi> correct(WidgetTester tester, FakeFlightApi a, Flight f) async {
    final finance = FakeFinanceApi();
    await tester.pumpWidget(pushHost(
        a, testUser(uid: 'adm', isAdmin: true, profile: null), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    return finance;
  }

  testWidgets('clôture sur un amphibie inactif : champ amerrissages présent', (tester) async {
    _useTallView(tester);
    final a = api()
      ..aircraft = [
        Aircraft.fromMap('amp',
            {'registration': 'F-JAMP', 'label': 'ULM A', 'active': false, 'amphibious': true}),
      ];
    final start = DateTime(2026, 10, 12, 5);
    final f = testFlight(
        id: 'w2', start: start, end: start.add(const Duration(minutes: 90)),
        crew: ['u1'], createdBy: 'u1', status: 'valide', aircraftId: 'amp', aircraft: 'F-JAMP');
    await tester.pumpWidget(pushHost(a, testUser(uid: 'u1', category: 'GAP'), flight: f));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clôturer'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('closing-water-landings')), findsOneWidget);
  });

  testWidgets('correction d\'un vol sur un amphibie inactif : amerrissages conservés',
      (tester) async {
    _useTallView(tester);
    final a = api()
      ..categories = {'u1': UserCategory.gap}
      ..aircraft = [
        ...api().aircraft,
        Aircraft.fromMap('amp',
            {'registration': 'F-JAMP', 'label': 'ULM A', 'active': false, 'amphibious': true}),
      ];
    final finance = await correct(tester, a, closedOn('ci1', 'amp', landings: 1));
    await tester.tap(find.text('Enregistrer la correction'));
    await tester.pumpAndSettle();
    expect(finance.adminUpdated['ci1']!['waterLandings'], 2);
  });

  testWidgets('correction d\'un vol avec amerrissages sur un appareil non amphibie : champ '
      'affiché, valeur envoyée (le serveur refuse)', (tester) async {
    _useTallView(tester);
    final a = api()..categories = {'u1': UserCategory.gap};
    final finance = await correct(tester, a, closedOn('ci2', 'a1', landings: 1));
    expect(find.byKey(const Key('correct-water-landings')), findsOneWidget);
    await tester.tap(find.text('Enregistrer la correction'));
    await tester.pumpAndSettle();
    expect(finance.adminUpdated['ci2']!['waterLandings'], 2);
  });

  testWidgets('correction sur un appareil non amphibie sans amerrissages : champ absent, '
      'non envoyé', (tester) async {
    _useTallView(tester);
    final a = api()..categories = {'u1': UserCategory.gap};
    final finance = await correct(tester, a, closedOn('ci3', 'a1', landings: 1, water: 0));
    expect(find.byKey(const Key('correct-water-landings')), findsNothing);
    await tester.tap(find.text('Enregistrer la correction'));
    await tester.pumpAndSettle();
    expect(finance.adminUpdated['ci3']!.containsKey('waterLandings'), isFalse);
  });

  // --- révision du 2026-10-01 : conflits en planification seulement ---

  testWidgets('aperçu : un vol clôturé ne crée jamais de conflit', (tester) async {
    _useTallView(tester);
    final a = api()
      ..flights = [
        testFlight(id: 'o', start: DateTime(2026, 10, 12, 9, 30), crew: ['lac'], aircraft: 'F-JABC',
            isClosed: true, actualFlightMinutes: 60),
      ];
    await tester.pumpWidget(host(a, testUser(uid: 'u1', profile: 'lache_toute_mission')));
    await tester.pumpAndSettle();
    await pickAircraft(tester);
    expect(preview(tester), isNot(contains('Conflit')));
  });

  testWidgets('correction admin d\'un vol clôturé qui chevauche un autre vol : aucun conflit',
      (tester) async {
    _useTallView(tester);
    final start = DateTime(2026, 10, 12, 5);
    final a = api()
      ..categories = {'u1': UserCategory.gap}
      ..flights = [
        testFlight(id: 'next', start: DateTime(2026, 10, 12, 6), crew: ['lac'], aircraft: 'F-JABC'),
      ];
    final f = testFlight(
        id: 'cc1', start: start, end: start.add(const Duration(minutes: 90)),
        crew: ['u1'], createdBy: 'u1', status: 'valide', isClosed: true,
        actualFlightMinutes: 90, billedAmount: 15000, billedTo: 'account');
    final finance = FakeFinanceApi();
    await tester.pumpWidget(pushHost(
        a, testUser(uid: 'adm', isAdmin: true, profile: null), flight: f, finance: finance));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    expect(preview(tester), isNot(contains('Conflit')));
    await tester.tap(find.text('Enregistrer la correction'));
    await tester.pumpAndSettle();
    expect(finance.adminUpdated.containsKey('cc1'), isTrue);
  });

  // --- confirmations et réponse perdue ---

  testWidgets('modification d\'une demande : « Demande modifiée, envoyée à INS. »', (tester) async {
    _useTallView(tester);
    final a = api()..updateStatus = FlightStatus.demande;
    final f = testFlight(
        id: 'rq', start: DateTime(2026, 10, 13, 9), status: 'demande',
        crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins');
    await tester.pumpWidget(pushHost(a, testUser(uid: 'u1', profile: 'eleve'), flight: f));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await save(tester);
    expect(find.text('planning'), findsOneWidget);
    expect(find.text('Demande modifiée, envoyée à INS.'), findsOneWidget);
  });

  testWidgets('validation : « Vol validé. »', (tester) async {
    _useTallView(tester);
    final f = testFlight(
        id: 'rq2', start: DateTime(2026, 10, 13, 9), status: 'demande',
        crew: ['u1', 'ins'], createdBy: 'u1', instructorUid: 'ins');
    await tester.pumpWidget(
        pushHost(api(), testUser(uid: 'ins', profile: 'instructeur'), flight: f));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Vol validé.'), findsOneWidget);
  });

  testWidgets('clôture : « Vol clôturé. »', (tester) async {
    _useTallView(tester);
    final start = DateTime(2026, 10, 12, 5);
    final f = testFlight(
        id: 'cl', start: start, end: start.add(const Duration(minutes: 90)),
        crew: ['u1'], createdBy: 'u1', status: 'valide');
    await tester.pumpWidget(pushHost(api(), testUser(uid: 'u1', category: 'GAP'), flight: f,
        finance: FakeFinanceApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clôturer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clôturer').last);
    await tester.pumpAndSettle();
    expect(find.text('Vol clôturé.'), findsOneWidget);
  });
}
