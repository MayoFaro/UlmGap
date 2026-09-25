import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/app.dart';
import 'package:ulmgap/core/env.dart';

// Banner dessine son texte (pas de widget Text) : on cherche le Banner lui-même.
final devBanner = find.byWidgetPredicate((w) => w is Banner && w.message == 'DEV');

void main() {
  testWidgets('bandeau DEV visible en dev', (tester) async {
    await tester.pumpWidget(const UlmGapApp(env: AppEnv.dev, home: Text('x')));
    expect(devBanner, findsOneWidget);
  });
  testWidgets('pas de bandeau en prod', (tester) async {
    await tester.pumpWidget(const UlmGapApp(env: AppEnv.prod, home: Text('x')));
    expect(devBanner, findsNothing);
  });
}
