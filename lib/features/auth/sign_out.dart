// Déconnexion propre (plan 5, revue finale) : plus aucune notification de
// ce compte sur l'appareil, même hors ligne ou sur un appareil partagé.
// Chaque étape a un délai : une écriture Firestore hors ligne ne se termine
// jamais, et la déconnexion ne doit pas en dépendre.
import '../../data/services.dart';

const _cleanupTimeout = Duration(seconds: 3);

/// Efface le jeton de [uid] (si connu), supprime celui de l'appareil, puis
/// déconnecte. Les échecs de nettoyage n'empêchent jamais la déconnexion :
/// un jeton supprimé sur l'appareil est déclaré invalide par FCM, et le
/// serveur l'efface au prochain envoi.
Future<void> signOutCleanly(AppServices services, {String? uid}) async {
  if (uid != null) {
    try {
      await services.users.saveFcmToken(uid, null).timeout(_cleanupTimeout);
    } catch (_) {}
  }
  try {
    await services.push?.deleteToken().timeout(_cleanupTimeout);
  } catch (_) {}
  await services.auth.signOut();
}
