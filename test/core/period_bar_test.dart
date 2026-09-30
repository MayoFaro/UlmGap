import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/formats.dart';
import 'package:ulmgap/core/period_bar.dart';

void main() {
  Future<void> pumpBar(WidgetTester tester, {bool enabled = true}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PeriodBar(
            from: DateTime(2026, 10, 1),
            to: DateTime(2026, 11, 1),
            enabled: enabled,
            onChanged: (_, __) {},
          ),
        ),
      ));

  testWidgets('affiche le premier et le dernier jour inclus', (tester) async {
    await pumpBar(tester);
    expect(find.text('Du ${formatDay(DateTime(2026, 10, 1))}'), findsOneWidget);
    expect(find.text('Au ${formatDay(DateTime(2026, 10, 31))}'), findsOneWidget);
  });

  testWidgets('choisir « Du » renvoie le jour choisi, « to » inchangé', (tester) async {
    List<DateTime>? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PeriodBar(
          from: DateTime(2026, 10, 1),
          to: DateTime(2026, 11, 1),
          onChanged: (f, t) => changed = [f, t],
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('period-from')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(changed, [DateTime(2026, 10, 10), DateTime(2026, 11, 1)]);
  });

  testWidgets('choisir « Au » renvoie le lendemain du jour choisi', (tester) async {
    List<DateTime>? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PeriodBar(
          from: DateTime(2026, 10, 1),
          to: DateTime(2026, 11, 1),
          onChanged: (f, t) => changed = [f, t],
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('period-to')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(changed, [DateTime(2026, 10, 1), DateTime(2026, 10, 21)]);
  });

  testWidgets('désactivé : boutons inactifs', (tester) async {
    await pumpBar(tester, enabled: false);
    final from = tester.widget<OutlinedButton>(find.byKey(const Key('period-from')));
    final to = tester.widget<OutlinedButton>(find.byKey(const Key('period-to')));
    expect(from.onPressed, isNull);
    expect(to.onPressed, isNull);
  });
}
