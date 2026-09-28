import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/auth_service.dart';

class _User implements User {
  _User(this.log);
  final List<String> log;

  @override
  Future<void> reload() async => log.add('reload');

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    log.add('token:$forceRefresh');
    return 't';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements FirebaseAuth {
  _Auth(this.user);
  final User user;

  @override
  User? get currentUser => user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('M1 : reload rafraîchit le jeton AVANT de recharger l\'utilisateur', () async {
    final log = <String>[];
    await FirebaseAuthService(_Auth(_User(log))).reload();
    expect(log, ['token:true', 'reload']);
  });
}
