import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/profile_badge.dart';
import 'package:ulmgap/core/profiles.dart';

void main() {
  final ref = jsonDecode(File('test/fixtures/referentials.json').readAsStringSync())
      as Map<String, dynamic>;

  test('codes de profil = référentiel partagé', () {
    expect(PilotProfile.values.map((p) => p.code).toList(), ref['profiles']);
  });

  test('codes de catégorie = référentiel partagé', () {
    expect(UserCategory.values.map((c) => c.code).toList(), ref['categories']);
  });

  test('fromCode', () {
    expect(PilotProfile.fromCode('lache_solo'), PilotProfile.lacheSolo);
    expect(PilotProfile.fromCode(null), isNull);
    expect(PilotProfile.fromCode('inconnu'), isNull);
    expect(UserCategory.fromCode('GR'), UserCategory.gr);
    expect(UserCategory.fromCode('MIL'), UserCategory.mil);
    expect(UserCategory.fromCode('???'), UserCategory.ext);
  });

  testWidgets('badge complet : icône et libellé', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ProfileBadge(profile: PilotProfile.eleve)),
    ));
    expect(find.text('Élève'), findsOneWidget);
    expect(find.byIcon(PilotProfile.eleve.icon), findsOneWidget);
  });

  testWidgets('badge compact : icône seule, libellé en infobulle', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ProfileBadge(profile: PilotProfile.instructeur, compact: true)),
    ));
    expect(find.text('Instructeur'), findsNothing);
    expect(find.byTooltip('Instructeur'), findsOneWidget);
  });

  testWidgets('pas de profil : rien', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ProfileBadge(profile: null)),
    ));
    expect(find.byType(Icon), findsNothing);
  });

  test('sortedByProfile : instructeurs, lâchés toutes missions, lâchés solo, élèves, non-pilotes ; puis nom', () {
    final people = [
      ('Zoé', PilotProfile.eleve),
      ('marc', null),
      ('Émile', PilotProfile.instructeur),
      ('Bruno', PilotProfile.lacheSolo),
      ('alain', PilotProfile.lacheToutesMissions),
      ('Damien', PilotProfile.instructeur),
      ('Anne', PilotProfile.eleve),
      ('Eric', PilotProfile.instructeur),
    ];
    final sorted = sortedByProfile(people, (p) => p.$2, (p) => p.$1).map((p) => p.$1).toList();
    expect(sorted, ['Damien', 'Émile', 'Eric', 'alain', 'Bruno', 'Anne', 'Zoé', 'marc']);
  });
}

