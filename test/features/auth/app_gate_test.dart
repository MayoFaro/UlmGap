import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/auth_service.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/auth/gate.dart';
import 'package:ulmgap/features/auth/no_access_screen.dart';
import 'package:ulmgap/features/home/home_shell.dart';

import '../../support/fakes.dart';

const verified = AuthSnapshot(uid: 'u1', email: 'a@b.fr', emailVerified: true);

Widget host(FakeAuthService auth, FakeUserRepository users) => AppServices(
      auth: auth,
      users: users,
      child: const MaterialApp(home: AppGate()),
    );

void main() {
  testWidgets('C1 : lecture refusée en cours de session → écran sans accès',
      (tester) async {
    final auth = FakeAuthService()..current = verified;
    final users = FakeUserRepository()..live = StreamController<AppUser?>();
    await tester.pumpWidget(host(auth, users));
    users.live!.add(testUser());
    await tester.pump();
    await tester.pump();
    expect(find.byType(HomeShell), findsOneWidget);

    // Compte désactivé : les règles refusent désormais la lecture de users/u1.
    users.live!.addError(Exception('permission-denied'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(NoAccessScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
  });

  testWidgets('I1 : un rafraîchissement du jeton (même uid) ne recrée pas l\'écoute',
      (tester) async {
    final auth = FakeAuthService()..current = verified;
    final users = FakeUserRepository()..users['u1'] = testUser();
    await tester.pumpWidget(host(auth, users));
    await tester.pump();
    await tester.pump();
    expect(find.byType(HomeShell), findsOneWidget);
    final before = users.watchCalls;

    auth.emit(verified); // même utilisateur, nouvel événement Auth
    await tester.pump();
    await tester.pump();
    expect(users.watchCalls, before);
    expect(find.byType(HomeShell), findsOneWidget);
  });
}
