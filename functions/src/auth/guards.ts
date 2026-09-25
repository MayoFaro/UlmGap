import { HttpsError } from "firebase-functions/v2/https";

export interface Caller { uid: string; token: { email_verified?: boolean } }

/** Connecté, e-mail vérifié, compte actif et admin, sinon HttpsError. */
export async function requireAdmin(
  db: FirebaseFirestore.Firestore,
  caller: Caller | undefined,
): Promise<void> {
  if (!caller) throw new HttpsError("unauthenticated", "Connexion requise.");
  if (caller.token.email_verified !== true) {
    throw new HttpsError("permission-denied", "E-mail non vérifié.");
  }
  const me = await db.collection("users").doc(caller.uid).get();
  if (!me.exists || me.get("active") !== true || me.get("isAdmin") !== true) {
    throw new HttpsError("permission-denied", "Réservé aux administrateurs.");
  }
}
