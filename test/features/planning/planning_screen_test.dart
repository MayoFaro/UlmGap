import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/flight/flight_texts.dart';
import 'package:ulmgap/features/planning/flight_card.dart';
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

bool _hasHighlightAncestor(Finder textFinder) => find
    .ancestor(
      of: textFinder,
      matching: find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == highlightFill),
    )
    .evaluate()
    .isNotEmpty;

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
    // L'en-tête d'appareils est affiché une seule fois, épinglé au-dessus de
    // la grille (fix planning : plus de répétition par jour).
    expect(find.text('ULM 1 (F-JABC)'), findsOneWidget);
    expect(find.text('ULM 2 (F-JXYZ)'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('col-a1')),
        matching: find.textContaining('09:00–10:00'),
      ),
      findsOneWidget,
    );
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

  testWidgets('grille par appareil : chaque colonne ne contient que ses propres vols', (tester) async {
    final a = api()
      ..flights = [
        testFlight(id: 'v1', start: DateTime(2026, 10, 12, 9), aircraftId: 'a1', aircraft: 'F-JABC'),
        testFlight(id: 'v2', start: DateTime(2026, 10, 12, 11), aircraftId: 'a2', aircraft: 'F-JXYZ'),
      ];
    await tester.pumpWidget(host(a, testUser()));
    await tester.pumpAndSettle();

    final v2Card = find.textContaining('11:00–12:00');
    expect(
      find.descendant(of: find.byKey(const Key('col-a2')), matching: v2Card),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const Key('col-a1')), matching: v2Card),
      findsNothing,
    );
  });

  testWidgets('trois appareils : défilement horizontal, sans débordement', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final a = FakeFlightApi()
      ..directory = [member('u1', 'JDU', 'eleve')]
      ..aircraft = [
        Aircraft.fromMap('a1', {'registration': 'F-AAA', 'label': 'A1', 'active': true}),
        Aircraft.fromMap('a2', {'registration': 'F-BBB', 'label': 'A2', 'active': true}),
        Aircraft.fromMap('a3', {'registration': 'F-CCC', 'label': 'A3', 'active': true}),
      ]
      ..flights = [
        testFlight(id: 'v3', start: DateTime(2026, 10, 12, 9),
            aircraftId: 'a3', aircraft: 'F-CCC', crew: ['u1']),
      ];
    await tester.pumpWidget(host(a, testUser()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.byKey(const Key('col-a3')).hitTestable(), findsNothing);

    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.byKey(const Key('col-a3')).hitTestable(), findsWidgets);
  });

  testWidgets(
      'après défilement horizontal : titre du jour toujours visible, en-tête A3 apparaît',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final a = FakeFlightApi()
      ..directory = [member('u1', 'JDU', 'eleve')]
      ..aircraft = [
        Aircraft.fromMap('a1', {'registration': 'F-AAA', 'label': 'A1', 'active': true}),
        Aircraft.fromMap('a2', {'registration': 'F-BBB', 'label': 'A2', 'active': true}),
        Aircraft.fromMap('a3', {'registration': 'F-CCC', 'label': 'A3', 'active': true}),
      ]
      ..flights = [
        testFlight(id: 'v3', start: DateTime(2026, 10, 12, 9),
            aircraftId: 'a3', aircraft: 'F-CCC', crew: ['u1']),
      ];
    await tester.pumpWidget(host(a, testUser()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Le titre du jour est hors du défilement horizontal : toujours visible.
    expect(tester.getTopLeft(find.text('lundi 12 octobre')).dx, greaterThanOrEqualTo(0));
    // L'en-tête (unique, épinglé) d'appareil A3 défile avec les colonnes :
    // hors écran avant le défilement.
    expect(find.byKey(const Key('head-a3')).hitTestable(), findsNothing);

    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Le titre du jour ne défile pas horizontalement : son bord gauche reste
    // dans la fenêtre visible (contrairement à un texte étiré sur la largeur
    // de la grille, dont le bord gauche sortirait de l'écran ici).
    expect(tester.getTopLeft(find.text('lundi 12 octobre')).dx, greaterThanOrEqualTo(0));
    // La ligne d'en-têtes défile en synchronisation avec les jours : A3
    // devient visible.
    expect(find.byKey(const Key('head-a3')).hitTestable(), findsOneWidget);
  });

  testWidgets('mise en évidence des vols où l\'utilisateur est dans l\'équipage', (tester) async {
    final a = api()
      ..flights = [
        testFlight(id: 'mine', start: DateTime(2026, 10, 12, 9), crew: ['u1', 'ins']),
        testFlight(id: 'other', start: DateTime(2026, 10, 12, 11),
            crew: ['ins'], aircraftId: 'a2', aircraft: 'F-JXYZ'),
      ];
    await tester.pumpWidget(host(a, testUser(uid: 'u1')));
    await tester.pumpAndSettle();

    expect(_hasHighlightAncestor(find.textContaining('09:00–10:00')), isTrue);
    expect(_hasHighlightAncestor(find.textContaining('11:00–12:00')), isFalse);
  });

  testWidgets(
      'en-tête d\'appareil unique par colonne, aligné avec les cartes (1600px)',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final a = api()
      ..flights = [
        testFlight(id: 'v1', start: DateTime(2026, 10, 12, 9), aircraftId: 'a1', aircraft: 'F-JABC'),
      ];
    await tester.pumpWidget(host(a, testUser()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Le premier en-tête n'est pas rogné à gauche.
    final headFinder = find.byKey(const Key('head-a1'));
    final headLeft = tester.getTopLeft(headFinder).dx;
    expect(headLeft, greaterThanOrEqualTo(0));

    // La carte de la colonne a1 démarre au même x que son en-tête (± 8 px).
    final cardFinder = find.descendant(
      of: find.byKey(const Key('col-a1')),
      matching: find.byType(FlightCard),
    );
    final cardLeft = tester.getTopLeft(cardFinder).dx;
    expect((cardLeft - headLeft).abs(), lessThanOrEqualTo(8));

    // La carte remplit (quasiment) la largeur de la colonne.
    final colWidth = tester.getSize(find.byKey(const Key('col-a1'))).width;
    final cardWidth = tester.getSize(cardFinder).width;
    expect(cardWidth, greaterThanOrEqualTo(colWidth - 16));
  });

  testWidgets('en-tête d\'appareils épinglée pendant le défilement vertical', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final a = api()
      ..flights = [
        for (var i = 0; i < 15; i++)
          testFlight(
              id: 'v$i',
              start: DateTime(2026, 10, 12 + i, 9),
              aircraftId: 'a1',
              aircraft: 'F-JABC'),
      ];
    await tester.pumpWidget(host(a, testUser()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('head-a1')).hitTestable(), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    // L'en-tête reste épinglé en haut malgré le défilement vertical.
    expect(find.byKey(const Key('head-a1')).hitTestable(), findsOneWidget);
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
