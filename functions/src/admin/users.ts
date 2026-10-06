import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, requireAdmin } from "../auth/guards";
import { asInvalid } from "../common/errors";
import { validateNewUser, validateUserPatch } from "./validation";

export async function createUser(caller: Caller | undefined, data: unknown): Promise<{ uid: string }> {
  const db = admin.firestore();
  await requireAdmin(db, caller);
  const input = asInvalid(() => validateNewUser(data));

  let uid: string;
  let adopted = false;
  try {
    const rec = await admin.auth().createUser({
      email: input.email, displayName: input.displayName, disabled: !input.active,
    });
    uid = rec.uid;
  } catch (e) {
    if ((e as { code?: string }).code !== "auth/email-already-exists") throw e;
    // Compte Auth sans document users (console, inscription directe, création
    // interrompue) : on le reprend au lieu de bloquer l'e-mail pour toujours.
    const existing = await admin.auth().getUserByEmail(input.email);
    if ((await db.collection("users").doc(existing.uid).get()).exists) {
      throw new HttpsError("already-exists", "Un compte existe déjà pour cet e-mail.");
    }
    await admin.auth().updateUser(existing.uid, {
      displayName: input.displayName, disabled: !input.active,
    });
    uid = existing.uid;
    adopted = true;
  }

  try {
    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();
    batch.set(db.collection("users").doc(uid), {
      ...input, balance: 0, fcmToken: null, createdAt: now, updatedAt: now,
    });
    batch.set(db.collection("profiles").doc(uid), {
      displayName: input.displayName, shortName: input.shortName,
      profile: input.profile, active: input.active,
      amphibiousCleared: input.amphibiousCleared,
    });
    await batch.commit();
  } catch (e) {
    // Pas de compte Auth sans document (sauf compte repris : on ne le supprime pas).
    if (!adopted) {
      await admin.auth().deleteUser(uid).catch((err) =>
        console.error("createUser: rollback deleteUser failed", uid, err));
    }
    throw e;
  }
  return { uid };
}

export async function updateUser(caller: Caller | undefined, data: unknown): Promise<void> {
  const db = admin.firestore();
  await requireAdmin(db, caller);
  const { uid, patch } = asInvalid(() => validateUserPatch(data));
  if (uid === caller!.uid && (patch.isAdmin === false || patch.active === false)) {
    throw new HttpsError("failed-precondition",
      "Vous ne pouvez pas retirer vos propres droits d'admin ni désactiver votre compte.");
  }
  const ref = db.collection("users").doc(uid);
  const current = await ref.get();
  if (!current.exists) throw new HttpsError("not-found", "Compte introuvable.");

  // Auth d'abord : s'il échoue, rien n'est écrit et l'admin peut relancer.
  // Si Firestore échoue ensuite, l'écart reste sans danger : les règles
  // lisent users.active, et un compte Auth désactivé ne se connecte plus.
  const authPatch: admin.auth.UpdateRequest = {};
  if (patch.active !== undefined) authPatch.disabled = !patch.active;
  if (patch.displayName !== undefined) authPatch.displayName = patch.displayName;
  if (Object.keys(authPatch).length > 0) await admin.auth().updateUser(uid, authPatch);

  const merged = { ...current.data(), ...patch };
  const batch = db.batch();
  batch.update(ref, { ...patch, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  // Toujours complet : un ancien compte sans profiles en obtient un entier.
  batch.set(db.collection("profiles").doc(uid), {
    displayName: merged.displayName ?? "",
    shortName: merged.shortName ?? "",
    profile: merged.profile ?? null,
    active: merged.active === true,
    amphibiousCleared: merged.amphibiousCleared === true,
  });
  await batch.commit();
}

export const adminCreateUser = onCall((req) =>
  createUser(req.auth as Caller | undefined, req.data));
export const adminUpdateUser = onCall((req) =>
  updateUser(req.auth as Caller | undefined, req.data));
