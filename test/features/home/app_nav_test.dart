import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/account/account_screen.dart';
import 'package:ulmgap/features/admin/pricing_admin_screen.dart';
import 'package:ulmgap/features/admin/users_admin_screen.dart';
import 'package:ulmgap/features/home/home_shell.dart';
import 'package:ulmgap/features/instructors/instructors_screen.dart';
import 'package:ulmgap/features/logbook/logbook_screen.dart';

import '../../support/fakes.dart';

Widget host(AppUser user) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      admin: FakeAdminApi(),
      flights: FakeFlightApi(),
      finance: FakeFinanceApi(),
      child: MaterialApp(home: HomeShell(user: user)),
    );

final admin = testUser(uid: 'adm', profile: 'instructeur', isAdmin: true);

Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip).last);
  await tester.pumpAndSettle();
}

Future<void> openAdmin(WidgetTester tester, String item) async {
  await tapTooltip(tester, 'Administration');
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('depuis le carnet, Mon compte s\'ouvre directement ; retour = accueil',
      (tester) async {
    await tester.pumpWidget(host(testUser(profile: 'eleve')));
    await tester.pump();
    await tapTooltip(tester, 'Carnet de vol');
    expect(find.byType(LogbookScreen), findsOneWidget);

    await tapTooltip(tester, 'Mon compte');
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.byType(LogbookScreen), findsNothing); // pas empilé

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byTooltip('Carnet de vol').hitTestable(), findsOneWidget);
  });

  testWidgets('l\'icône de l\'écran affiché est désactivée', (tester) async {
    await tester.pumpWidget(host(testUser(profile: 'eleve')));
    await tester.pump();
    await tapTooltip(tester, 'Carnet de vol');
    final button = tester.widget<IconButton>(find.ancestor(
        of: find.byTooltip('Carnet de vol').last, matching: find.byType(IconButton)).first);
    expect(button.onPressed, isNull);
  });

  testWidgets('admin : les icônes suivent sur chaque écran', (tester) async {
    await tester.pumpWidget(host(admin));
    await tester.pump();

    await tapTooltip(tester, 'Instructeurs');
    expect(find.byType(InstructorsScreen), findsOneWidget);
    await openAdmin(tester, 'Tarifs');
    expect(find.byType(PricingAdminScreen), findsOneWidget);
    await openAdmin(tester, 'Comptes');
    expect(find.byType(UsersAdminScreen), findsOneWidget);
    await tapTooltip(tester, 'Carnet de vol');
    expect(find.byType(LogbookScreen), findsOneWidget);
    await tapTooltip(tester, 'Instructeurs');
    expect(find.byType(InstructorsScreen), findsOneWidget);

    // Un seul écran au-dessus de l'accueil.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(InstructorsScreen), findsNothing);
  });

  testWidgets('admin sur 360 px : Mon compte (avec Se déconnecter) sans débordement',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(admin));
    await tester.pump();
    await tapTooltip(tester, 'Mon compte');
    expect(tester.takeException(), isNull);
    for (final t in ['Carnet de vol', 'Instructeurs', 'Administration', 'Se déconnecter']) {
      expect(find.byTooltip(t).hitTestable(), findsOneWidget, reason: t);
    }
  });
}
