import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/flight.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/logbook/logbook_screen.dart';
import 'package:ulmgap/features/account/account_screen.dart';
import 'package:ulmgap/features/admin/billing_report_screen.dart';
import 'package:ulmgap/features/admin/pricing_admin_screen.dart';
import 'package:ulmgap/features/home/home_shell.dart';
import 'package:ulmgap/features/flight/flight_screen.dart';
import 'package:ulmgap/features/planning/planning_screen.dart';
import 'package:ulmgap/features/instructors/instructors_screen.dart';

import '../../support/fakes.dart';

Widget host(AppUser user) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      flights: FakeFlightApi(),
      finance: FakeFinanceApi(),
      child: MaterialApp(home: HomeShell(user: user)),
    );

void main() {
  testWidgets('icône Mon compte : visible pour tous, ouvre AccountScreen',
      (tester) async {
    await tester.pumpWidget(host(testUser(profile: 'eleve')));
    await tester.pump();
    expect(find.byTooltip('Mon compte'), findsOneWidget);
    await tester.tap(find.byTooltip('Mon compte'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);
  });

  testWidgets('icône Pilotes : absente pour un élève', (tester) async {
    await tester.pumpWidget(host(testUser(profile: 'eleve')));
    await tester.pump();
    expect(find.byTooltip('Pilotes'), findsNothing);
  });

  testWidgets('icône Pilotes : présente pour un instructeur, ouvre InstructorsScreen',
      (tester) async {
    await tester.pumpWidget(host(testUser(profile: 'instructeur')));
    await tester.pump();
    expect(find.byTooltip('Pilotes'), findsOneWidget);
    await tester.tap(find.byTooltip('Pilotes'));
    await tester.pumpAndSettle();
    expect(find.byType(InstructorsScreen), findsOneWidget);
  });

  testWidgets('icône Pilotes : présente pour un admin non instructeur',
      (tester) async {
    await tester.pumpWidget(host(testUser(profile: 'eleve', isAdmin: true)));
    await tester.pump();
    expect(find.byTooltip('Pilotes'), findsOneWidget);
  });

  testWidgets('menu Administration : Tarifs ouvre PricingAdminScreen', (tester) async {
    await tester.pumpWidget(host(testUser(isAdmin: true)));
    await tester.pump();
    await tester.tap(find.byTooltip('Administration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tarifs'));
    await tester.pumpAndSettle();
    expect(find.byType(PricingAdminScreen), findsOneWidget);
  });

  testWidgets('menu Administration : Relevé des vols facturés ouvre BillingReportScreen',
      (tester) async {
    await tester.pumpWidget(host(testUser(isAdmin: true)));
    await tester.pump();
    await tester.tap(find.byTooltip('Administration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Relevé des vols facturés'));
    await tester.pumpAndSettle();
    expect(find.byType(BillingReportScreen), findsOneWidget);
  });

  testWidgets('icône Carnet de vol : visible pour tous, ouvre le carnet', (tester) async {
    await tester.pumpWidget(host(testUser(profile: 'eleve')));
    await tester.pump();
    await tester.tap(find.byTooltip('Carnet de vol'));
    await tester.pumpAndSettle();
    expect(find.byType(LogbookScreen), findsOneWidget);
  });

  testWidgets('plus de « Se déconnecter » dans la barre d\'accueil', (tester) async {
    await tester.pumpWidget(host(testUser(isAdmin: true)));
    await tester.pump();
    expect(find.byTooltip('Se déconnecter'), findsNothing);
    expect(find.byTooltip('Vols effectués'), findsNothing);
    expect(find.byTooltip('Compteurs'), findsNothing);
  });

  testWidgets('admin sur 360 px de large : pas de débordement, 4 icônes accessibles',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(testUser(profile: 'instructeur', isAdmin: true)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (final t in ['Carnet de vol', 'Mon compte', 'Pilotes', 'Administration']) {
      expect(find.byTooltip(t).hitTestable(), findsOneWidget, reason: t);
    }
  });

  group('rappel de clôture au lancement', () {
    final now = DateTime(2026, 10, 12, 14);

    /// Accueil avec [flights] servis par les deux API (fiche du vol comprise).
    Widget reminderHost(AppUser user, List<Flight> flights) => AppServices(
          auth: FakeAuthService(),
          users: FakeUserRepository(),
          flights: FakeFlightApi()..flights = flights,
          finance: FakeFinanceApi()..flights = flights,
          child: MaterialApp(home: HomeShell(user: user, now: () => now)),
        );

    final ended = testFlight(id: 'ended', crew: ['u1'],
        start: DateTime(2026, 10, 12, 9), end: DateTime(2026, 10, 12, 10));

    testWidgets('vol terminé non clôturé de mon équipage : sa fiche s\'ouvre ; retour = accueil',
        (tester) async {
      await tester.pumpWidget(reminderHost(testUser(uid: 'u1', profile: 'eleve'), [ended]));
      await tester.pumpAndSettle();
      final screen = tester.widget<FlightScreen>(find.byType(FlightScreen));
      expect(screen.flight!.id, 'ended');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(FlightScreen), findsNothing);
      expect(find.byType(PlanningScreen), findsOneWidget);
    });

    testWidgets('aucun vol à clôturer pour moi : l\'accueil reste affiché', (tester) async {
      final other = testFlight(id: 'other', crew: ['u2'],
          start: DateTime(2026, 10, 12, 9), end: DateTime(2026, 10, 12, 10));
      final running = testFlight(id: 'running', crew: ['u1'],
          start: DateTime(2026, 10, 12, 13), end: DateTime(2026, 10, 12, 15));
      await tester.pumpWidget(
          reminderHost(testUser(uid: 'u1', profile: 'eleve'), [other, running]));
      await tester.pumpAndSettle();
      expect(find.byType(FlightScreen), findsNothing);
    });

    testWidgets('une seule fois : une reconstruction de l\'accueil ne rouvre pas la fiche',
        (tester) async {
      final user = testUser(uid: 'u1', profile: 'eleve');
      await tester.pumpWidget(reminderHost(user, [ended]));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(reminderHost(user, [ended]));
      await tester.pumpAndSettle();
      expect(find.byType(FlightScreen), findsNothing);
    });
  });
}
