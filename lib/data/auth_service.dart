import 'package:firebase_auth/firebase_auth.dart';

class AuthSnapshot {
  const AuthSnapshot({required this.uid, required this.email, required this.emailVerified});
  final String uid;
  final String email;
  final bool emailVerified;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

String authErrorMessage(String code) {
  switch (code) {
    case 'wrong-password':
    case 'user-not-found':
    case 'invalid-credential':
    case 'invalid-email':
      return 'E-mail ou mot de passe incorrect.';
    case 'user-disabled':
      return 'Ce compte est désactivé.';
    case 'too-many-requests':
      return 'Trop de tentatives. Réessayez plus tard.';
    case 'network-request-failed':
      return 'Pas de connexion réseau.';
    default:
      return 'Connexion impossible ($code).';
  }
}

abstract class AuthService {
  /// Émet à chaque changement de session ET après reload() (e-mail vérifié).
  Stream<AuthSnapshot?> changes();
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);
  Future<void> sendEmailVerification();
  Future<void> reload();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService([FirebaseAuth? auth]) : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;

  @override
  Stream<AuthSnapshot?> changes() => _auth.userChanges().map((u) => u == null
      ? null
      : AuthSnapshot(uid: u.uid, email: u.email ?? '', emailVerified: u.emailVerified));

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(authErrorMessage(e.code));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(authErrorMessage(e.code));
    }
  }

  @override
  Future<void> sendEmailVerification() async =>
      _auth.currentUser?.sendEmailVerification();

  @override
  Future<void> reload() async {
    // Jeton d'abord : reload() déclenche userChanges(), et l'écoute de
    // users/{uid} qui s'ouvre alors doit porter email_verified (règles).
    await _auth.currentUser?.getIdToken(true);
    await _auth.currentUser?.reload();
  }
}
