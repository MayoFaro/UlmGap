import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';

abstract class UserRepository {
  Stream<AppUser?> watchUser(String uid);
}

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  @override
  Stream<AppUser?> watchUser(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((s) => s.exists ? AppUser.fromMap(s.id, s.data()!) : null)
      // Lecture refusée (inactif / non vérifié) → pas d'accès.
      .handleError((Object _) {}, test: (e) => e is FirebaseException);
}
