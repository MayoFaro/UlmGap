// Notifications push (plan 5) : jeton FCM de l'appareil et messages reçus
// app ouverte. Android et web ; iOS viendra plus tard (clés APNs).
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

abstract class PushService {
  /// Demande la permission puis rend le jeton ; null si refusée ou si le web
  /// n'a pas de clé VAPID.
  Future<String?> token();
  Stream<String> get onTokenRefresh;
  Stream<({String title, String body})> get onForegroundMessage;
  Future<void> deleteToken();
}

class FirebasePushService implements PushService {
  FirebasePushService({required this.webVapidKey, FirebaseMessaging? messaging})
      : _m = messaging ?? FirebaseMessaging.instance;

  final String webVapidKey;
  final FirebaseMessaging _m;

  @override
  Future<String?> token() async {
    if (kIsWeb && webVapidKey.isEmpty) return null;
    final settings = await _m.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
    return _m.getToken(vapidKey: kIsWeb ? webVapidKey : null);
  }

  @override
  Stream<String> get onTokenRefresh => _m.onTokenRefresh;

  @override
  Stream<({String title, String body})> get onForegroundMessage => FirebaseMessaging.onMessage
      .where((m) => m.notification != null)
      .map((m) => (title: m.notification!.title ?? '', body: m.notification!.body ?? ''));

  @override
  Future<void> deleteToken() => _m.deleteToken();
}
