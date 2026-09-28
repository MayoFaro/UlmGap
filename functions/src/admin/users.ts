import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, requireAdmin } from "../auth/guards";
import { ValidationError, validateNewUser, validateUserPatch } from "./validation";

function asInvalid<T>(fn: () => T): T {
  try {
    return fn();
  } catch (e) {
    if (e instanceof ValidationError) throw new HttpsError("invalid-argument", e.message);
    throw e;
  }
}

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
  if (!(await ref.get()).exists) throw new HttpsError("not-found", "Compte introuvable.");

  const batch = db.batch();
  batch.update(ref, { ...patch, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  const pub: Record<string, unknown> = {};
  for (const k of ["displayName", "shortName", "profile", "active"] as const) {
    if (k in patch) pub[k] = patch[k];
  }
  if (Object.keys(pub).length > 0) batch.set(db.collection("profiles").doc(uid), pub, { merge: true });
  await batch.commit();

  const authPatch: admin.auth.UpdateRequest = {};
  if (patch.active !== undefined) authPatch.disabled = !patch.active;
  if (patch.displayName !== undefined) authPatch.displayName = patch.displayName;
  if (Object.keys(authPatch).length > 0) await admin.auth().updateUser(uid, authPatch);
}

export const adminCreateUser = onCall((req) =>
  createUser(req.auth as Caller | undefined, req.data));
export const adminUpdateUser = onCall((req) =>
  updateUser(req.auth as Caller | undefined, req.data));
