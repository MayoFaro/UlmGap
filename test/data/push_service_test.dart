import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/push_service.dart';

void main() {
  test('jeton demandé seulement si les notifications sont autorisées', () {
    expect(pushAllowed(AuthorizationStatus.authorized), isTrue);
    expect(pushAllowed(AuthorizationStatus.provisional), isTrue);
    // Fenêtre fermée sans choix (web « default ») : pas de getToken, sinon le
    // navigateur redemanderait à chaque lancement.
    expect(pushAllowed(AuthorizationStatus.notDetermined), isFalse);
    expect(pushAllowed(AuthorizationStatus.denied), isFalse);
  });
}
