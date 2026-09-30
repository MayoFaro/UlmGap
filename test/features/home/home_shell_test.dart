import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/logbook/logbook_screen.dart';
import 'package:ulmgap/features/account/account_screen.dart';
import 'package:ulmgap/features/admin/billing_report_screen.dart';
import 'package:ulmgap/features/admin/pricing_admin_screen.dart';
import 'package:ulmgap/features/home/home_shell.dart';
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

  testWidgets('icône Instructeurs : absente pour un élève', (tester) async {
    await tester.pumpWidget(host(testUser(profile: 'eleve')));
    await tester.pump();
    expect(find.byTooltip('Instructeurs'), findsNothing);
  });

  testWidgets('icône Instructeurs : présente pour un instructeur, ouvre InstructorsScreen',
      (tester) async {
    await tester.pumpWidget(host(testUser(profile: 'instructeur')));
    await tester.pump();
    expect(find.byTooltip('Instructeurs'), findsOneWidget);
    await tester.tap(find.byTooltip('Instructeurs'));
    await tester.pumpAndSettle();
    expect(find.byType(InstructorsScreen), findsOneWidget);
  });

  testWidgets('icône Instructeurs : présente pour un admin non instructeur',
      (tester) async {
    await tester.pumpWidget(host(testUser(profile: 'eleve', isAdmin: true)));
    await tester.pump();
    expect(find.byTooltip('Instructeurs'), findsOneWidget);
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
    for (final t in ['Carnet de vol', 'Mon compte', 'Instructeurs', 'Administration']) {
      expect(find.byTooltip(t).hitTestable(), findsOneWidget, reason: t);
    }
  });
}
