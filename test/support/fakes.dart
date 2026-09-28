import 'dart:async';

import 'package:ulmgap/data/admin_api.dart';
import 'package:ulmgap/data/aircraft.dart';
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
  int watchCalls = 0;

  /// Si défini, watchUser renvoie ce flux (pour simuler erreurs et mises à jour).
  StreamController<AppUser?>? live;

  @override
  Stream<AppUser?> watchUser(String uid) {
    watchCalls++;
    return live?.stream ?? Stream.value(users[uid]);
  }
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

// --- ajouts Task 8 ---
class FakeAdminApi implements AdminApi {
  final usersCtrl = StreamController<List<AppUser>>.broadcast();
  final aircraftCtrl = StreamController<List<Aircraft>>.broadcast();
  List<AppUser> users = [];
  List<Aircraft> aircraft = [];
  final created = <Map<String, dynamic>>[];
  final updated = <String, Map<String, dynamic>>{};
  final upserted = <Map<String, dynamic>>[];

  @override
  Stream<List<AppUser>> watchAllUsers() async* {
    yield users;
    yield* usersCtrl.stream;
  }

  @override
  Future<String> createUser(Map<String, dynamic> input) async {
    created.add(input);
    return 'new-uid';
  }

  @override
  Future<void> updateUser(String uid, Map<String, dynamic> patch) async => updated[uid] = patch;

  @override
  Stream<List<Aircraft>> watchAircraft() async* {
    yield aircraft;
    yield* aircraftCtrl.stream;
  }

  @override
  Future<String> upsertAircraft(Map<String, dynamic> input) async {
    upserted.add(input);
    return 'a-new';
  }
}
