import { HttpsError } from "firebase-functions/v2/https";
import type { Profile } from "../admin/validation";

export interface Caller { uid: string; token: { email_verified?: boolean } }

export interface CallerProfile {
  uid: string;
  profile: Profile | null;
  isAdmin: boolean;
  category: string;
}

/** Connecté, e-mail vérifié et compte actif, sinon HttpsError. */
export async function requireActiveUser(
  db: FirebaseFirestore.Firestore,
  caller: Caller | undefined,
): Promise<CallerProfile> {
  if (!caller) throw new HttpsError("unauthenticated", "Connexion requise.");
  if (caller.token.email_verified !== true) {
    throw new HttpsError("permission-denied", "E-mail non vérifié.");
  }
  const me = await db.collection("users").doc(caller.uid).get();
  if (!me.exists || me.get("active") !== true) {
    throw new HttpsError("permission-denied", "Compte inactif ou inconnu.");
  }
  return {
    uid: caller.uid,
    profile: (me.get("profile") as Profile | null | undefined) ?? null,
    isAdmin: me.get("isAdmin") === true,
    category: (me.get("category") as string | undefined) ?? "EXT",
  };
}

/** Utilisateur actif et admin, sinon HttpsError. */
export async function requireAdmin(
  db: FirebaseFirestore.Firestore,
  caller: Caller | undefined,
): Promise<void> {
  const me = await requireActiveUser(db, caller);
  if (!me.isAdmin) throw new HttpsError("permission-denied", "Réservé aux administrateurs.");
}
