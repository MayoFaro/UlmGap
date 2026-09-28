import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/profile_badge.dart';
import 'package:ulmgap/data/services.dart';
import 'package:ulmgap/features/admin/users_admin_screen.dart';

import '../../support/fakes.dart';

Widget host(FakeAdminApi api) => AppServices(
      auth: FakeAuthService(),
      users: FakeUserRepository(),
      admin: api,
      child: const MaterialApp(home: UsersAdminScreen()),
    );

void main() {
  testWidgets('liste : nom, code, badge, catégorie, inactif signalé', (tester) async {
    final api = FakeAdminApi()
      ..users = [testUser(uid: 'u1'), testUser(uid: 'u2', active: false, profile: 'instructeur')];
    await tester.pumpWidget(host(api));
    await tester.pump();
    expect(find.text('Jean Dupont'), findsNWidgets(2));
    expect(find.byType(ProfileBadge), findsNWidgets(2));
    expect(find.text('EXT'), findsNWidgets(2));
    expect(find.text('Désactivé'), findsOneWidget);
  });

  testWidgets('création : envoie les champs normalisés', (tester) async {
    final api = FakeAdminApi();
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.tap(find.byTooltip('Nouveau compte'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('f-email')), ' Pilote@Club.fr ');
    await tester.enterText(find.byKey(const Key('f-name')), 'Paul Martin');
    await tester.enterText(find.byKey(const Key('f-short')), 'pma');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.created.single, {
      'email': 'pilote@club.fr',
      'displayName': 'Paul Martin',
      'shortName': 'PMA',
      'profile': 'eleve',
      'category': 'EXT',
      'isAdmin': false,
      'active': true,
    });
  });

  testWidgets('création : e-mail invalide bloque l\'envoi', (tester) async {
    final api = FakeAdminApi();
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.tap(find.byTooltip('Nouveau compte'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('f-email')), 'nope');
    await tester.enterText(find.byKey(const Key('f-name')), 'Paul');
    await tester.enterText(find.byKey(const Key('f-short')), 'PMA');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.created, isEmpty);
    expect(find.text('E-mail invalide.'), findsOneWidget);
  });

  testWidgets('modification : n\'envoie pas l\'e-mail', (tester) async {
    final api = FakeAdminApi()..users = [testUser(uid: 'u1')];
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.tap(find.text('Jean Dupont'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.updated['u1']!.containsKey('email'), isFalse);
    expect(api.updated['u1']!['shortName'], 'JDU');
  });

  testWidgets('I3 : compte créé mais lien non envoyé → message explicite', (tester) async {
    final api = FakeAdminApi()..failPasswordLink = true;
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.tap(find.byTooltip('Nouveau compte'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('f-email')), 'p@club.fr');
    await tester.enterText(find.byKey(const Key('f-name')), 'Paul');
    await tester.enterText(find.byKey(const Key('f-short')), 'PMA');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Compte créé, mais'), findsOneWidget);
  });

  testWidgets('I3 : « Envoyer le lien de mot de passe » depuis la liste', (tester) async {
    final api = FakeAdminApi()..users = [testUser(uid: 'u1')];
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.tap(find.byTooltip('Envoyer le lien de mot de passe'));
    await tester.pumpAndSettle();
    expect(api.linksSent, ['jean@club.fr']);
  });

  testWidgets('M6 : chargement, erreur et liste vide', (tester) async {
    final api = FakeAdminApi()..hold = true;
    await tester.pumpWidget(host(api));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(host(FakeAdminApi()..error = Exception('refus')));
    await tester.pump();
    expect(find.text('Impossible de charger les données. Vérifiez la connexion.'),
        findsOneWidget);

    await tester.pumpWidget(host(FakeAdminApi()));
    await tester.pump();
    expect(find.text('Aucun compte.'), findsOneWidget);
  });
}
