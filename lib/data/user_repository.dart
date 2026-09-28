import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';

abstract class UserRepository {
  Stream<AppUser?> watchUser(String uid);
}

/// Toute erreur (lecture refusée : compte désactivé, e-mail non vérifié…)
/// devient `null` = « pas d'accès ». Surtout ne pas l'avaler : l'écran
/// resterait sur le dernier état (compte actif).
Stream<T?> nullOnError<T>(Stream<T?> source) => source.transform(
      StreamTransformer<T?, T?>.fromHandlers(
        handleError: (Object _, StackTrace __, EventSink<T?> sink) => sink.add(null),
      ),
    );

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  @override
  Stream<AppUser?> watchUser(String uid) => nullOnError(_db
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((s) => s.exists ? AppUser.fromMap(s.id, s.data()!) : null));
}
