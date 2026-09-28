import 'dart:async';

import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/auth_service.dart';
import 'package:ulmgap/data/user_repository.dart';

class FakeAuthService implements AuthService {
  final _ctrl = StreamController<AuthSnapshot?>.broadcast();
  AuthSnapshot? current;
  final calls = <String>[];
  String? failWith; // message d'AuthFailure à lever sur signIn

  void emit(AuthSnapshot? s) {
    current = s;
    _ctrl.add(s);
  }

  @override
  Stream<AuthSnapshot?> changes() async* {
    yield current;
    yield* _ctrl.stream;
  }

  @override
  Future<void> signIn(String email, String password) async {
    calls.add('signIn:$email');
    if (failWith != null) throw AuthFailure(failWith!);
  }

  @override
  Future<void> signOut() async => calls.add('signOut');
  @override
  Future<void> sendPasswordReset(String email) async => calls.add('reset:$email');
  @override
  Future<void> sendEmailVerification() async => calls.add('verify');
  @override
  Future<void> reload() async => calls.add('reload');
}

class FakeUserRepository implements UserRepository {
  final users = <String, AppUser>{};
  @override
  Stream<AppUser?> watchUser(String uid) => Stream.value(users[uid]);
}

AppUser testUser({
  String uid = 'u1',
  bool active = true,
  bool isAdmin = false,
  String? profile = 'eleve',
}) =>
    AppUser.fromMap(uid, {
      'displayName': 'Jean Dupont',
      'shortName': 'JDU',
      'email': 'jean@club.fr',
      'profile': profile,
      'category': 'EXT',
      'isAdmin': isAdmin,
      'active': active,
      'balance': 0,
    });
