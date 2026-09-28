import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, requireAdmin } from "../auth/guards";
import { asInvalid } from "../common/errors";
import { validateAircraft } from "./validation";

export async function upsertAircraft(caller: Caller | undefined, data: unknown): Promise<{ id: string }> {
  const db = admin.firestore();
  await requireAdmin(db, caller);
  const a = asInvalid(() => validateAircraft(data));
  const col = db.collection("aircraft");
  const regs = db.collection("aircraftRegistrations");
  const ref = a.id ? col.doc(a.id) : col.doc();

  await db.runTransaction(async (tx) => {
    const current = a.id ? await tx.get(ref) : null;
    if (current && !current.exists) throw new HttpsError("not-found", "Appareil introuvable.");
    // La réservation (un document par immatriculation) sérialise les créations
    // simultanées ; la requête couvre les appareils créés avant les réservations.
    const reservation = await tx.get(regs.doc(a.registration));
    const legacy = await tx.get(col.where("registration", "==", a.registration));
    if ((reservation.exists && reservation.get("aircraftId") !== ref.id) ||
        legacy.docs.some((d) => d.id !== ref.id)) {
      throw new HttpsError("already-exists", "Cette immatriculation existe déjà.");
    }
    const previous = current?.get("registration") as string | undefined;
    if (previous && previous !== a.registration) tx.delete(regs.doc(previous));
    tx.set(regs.doc(a.registration), { aircraftId: ref.id });
    tx.set(ref, {
      registration: a.registration, label: a.label, active: a.active,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  return { id: ref.id };
}

export const adminUpsertAircraft = onCall((req) =>
  upsertAircraft(req.auth as Caller | undefined, req.data));
