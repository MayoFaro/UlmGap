import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/profile_badge.dart';
import 'package:ulmgap/core/profiles.dart';
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
      'amphibiousCleared': false,
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

  testWidgets('plan 10 : case « Lâché amphibie » pré-cochée et envoyée en modification',
      (tester) async {
    final api = FakeAdminApi()..users = [testUser(uid: 'u1', amphibiousCleared: true)];
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.tap(find.text('Jean Dupont'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('user-amphibious'))).value, isTrue);
    await tester.tap(find.byKey(const Key('user-amphibious')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.updated['u1']!['amphibiousCleared'], isFalse);
  });

  testWidgets('plan 10 : en création, la case est décochée puis envoyée cochée',
      (tester) async {
    final api = FakeAdminApi();
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.tap(find.byTooltip('Nouveau compte'));
    await tester.pumpAndSettle();
    expect(find.text('Lâché amphibie'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('user-amphibious'))).value, isFalse);
    await tester.enterText(find.byKey(const Key('f-email')), 'p@club.fr');
    await tester.enterText(find.byKey(const Key('f-name')), 'Paul');
    await tester.enterText(find.byKey(const Key('f-short')), 'PMA');
    await tester.tap(find.byKey(const Key('user-amphibious')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(api.created.single['amphibiousCleared'], isTrue);
  });

  testWidgets('plan 10 : le menu Profil montre l\'icône de chaque profil pilote',
      (tester) async {
    final api = FakeAdminApi();
    await tester.pumpWidget(host(api));
    await tester.pump();
    await tester.tap(find.byTooltip('Nouveau compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Élève'));
    await tester.pumpAndSettle();
    for (final p in PilotProfile.values) {
      final item = find.ancestor(
          of: find.text(p.label), matching: find.byType(DropdownMenuItem<PilotProfile?>));
      expect(
          find.descendant(
              of: item.last,
              matching: find.byWidgetPredicate((w) => w is ProfileBadge && w.profile == p)),
          findsOneWidget,
          reason: p.label);
    }
    final none = find.ancestor(
        of: find.text('Non pilote'), matching: find.byType(DropdownMenuItem<PilotProfile?>));
    expect(find.descendant(of: none.last, matching: find.byType(ProfileBadge)), findsNothing);
  });

  testWidgets('plan 10 : « amphibie » visible dans la liste pour un compte lâché amphibie',
      (tester) async {
    final api = FakeAdminApi()
      ..users = [
        testUser(uid: 'u1', amphibiousCleared: true),
        testUser(uid: 'u2', shortName: 'ABC'),
      ];
    await tester.pumpWidget(host(api));
    await tester.pump();
    expect(find.text('amphibie'), findsOneWidget);
  });
}
