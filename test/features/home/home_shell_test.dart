import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/account/account_screen.dart';
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
}
