import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/core/async_state.dart';

void main() {
  test('données présentes : rien à afficher', () {
    const snap = AsyncSnapshot<List<int>>.withData(ConnectionState.active, [1]);
    expect(asyncState(snap, isEmpty: false, empty: 'Vide'), isNull);
  });

  testWidgets('chargement, erreur, vide', (tester) async {
    Future<void> show(AsyncSnapshot<List<int>> s, bool isEmpty) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: asyncState(s, isEmpty: isEmpty, empty: 'Vide')!)));

    await show(const AsyncSnapshot<List<int>>.waiting(), true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await show(const AsyncSnapshot<List<int>>.withError(ConnectionState.active, 'x'), true);
    expect(find.text('Impossible de charger les données. Vérifiez la connexion.'),
        findsOneWidget);

    await show(const AsyncSnapshot<List<int>>.withData(ConnectionState.active, []), true);
    expect(find.text('Vide'), findsOneWidget);
  });
}
