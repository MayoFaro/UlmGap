import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, requireAdmin } from "../auth/guards";
import { ValidationError, validateAircraft } from "./validation";

export async function upsertAircraft(caller: Caller | undefined, data: unknown): Promise<{ id: string }> {
  const db = admin.firestore();
  await requireAdmin(db, caller);
  let a: ReturnType<typeof validateAircraft>;
  try {
    a = validateAircraft(data);
  } catch (e) {
    if (e instanceof ValidationError) throw new HttpsError("invalid-argument", e.message);
    throw e;
  }
  const col = db.collection("aircraft");
  const ref = a.id ? col.doc(a.id) : col.doc();
  if (a.id && !(await ref.get()).exists) throw new HttpsError("not-found", "Appareil introuvable.");

  const same = await col.where("registration", "==", a.registration).get();
  if (same.docs.some((d) => d.id !== ref.id)) {
    throw new HttpsError("already-exists", "Cette immatriculation existe déjà.");
  }
  await ref.set({
    registration: a.registration, label: a.label, active: a.active,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { id: ref.id };
}

export const adminUpsertAircraft = onCall((req) =>
  upsertAircraft(req.auth as Caller | undefined, req.data));
