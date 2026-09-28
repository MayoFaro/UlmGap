import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'aircraft.dart';
import 'app_user.dart';

abstract class AdminApi {
  Stream<List<AppUser>> watchAllUsers();
  Future<String> createUser(Map<String, dynamic> input);
  Future<void> updateUser(String uid, Map<String, dynamic> patch);
  Stream<List<Aircraft>> watchAircraft();
  Future<String> upsertAircraft(Map<String, dynamic> input);
}

class FirebaseAdminApi implements AdminApi {
  FirebaseAdminApi({FirebaseFirestore? db, FirebaseFunctions? fn, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _fn = fn ?? FirebaseFunctions.instanceFor(region: 'europe-west1'),
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;
  final FirebaseAuth _auth;

  @override
  Stream<List<AppUser>> watchAllUsers() => _db
      .collection('users')
      .orderBy('displayName')
      .snapshots()
      .map((q) => q.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList());

  @override
  Future<String> createUser(Map<String, dynamic> input) async {
    final res = await _fn.httpsCallable('adminCreateUser').call(input);
    // Le nouvel utilisateur reçoit le lien pour définir son mot de passe.
    await _auth.sendPasswordResetEmail(email: input['email'] as String);
    return (res.data as Map)['uid'] as String;
  }

  @override
  Future<void> updateUser(String uid, Map<String, dynamic> patch) =>
      _fn.httpsCallable('adminUpdateUser').call({'uid': uid, ...patch});

  @override
  Stream<List<Aircraft>> watchAircraft() => _db
      .collection('aircraft')
      .orderBy('label')
      .snapshots()
      .map((q) => q.docs.map((d) => Aircraft.fromMap(d.id, d.data())).toList());

  @override
  Future<String> upsertAircraft(Map<String, dynamic> input) async {
    final res = await _fn.httpsCallable('adminUpsertAircraft').call(input);
    return (res.data as Map)['id'] as String;
  }
}
