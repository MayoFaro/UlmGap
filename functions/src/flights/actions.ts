import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, CallerProfile, requireActiveUser } from "../auth/guards";
import { asInvalid } from "../common/errors";
import type { PricingMode } from "../rules/flights";
import type { Pricing } from "../rules/pricing";
import { assertNotStarted, loadFlight, planFlight, touchLocks } from "./core";
import {
  FlightInput, checkDuration, checkHorizon, validateFlightId, validateRefusal, validateReviewChanges,
} from "./validation";
import { notifyFlight } from "../notify/flight-info";
import { cancelledPush, refusedPush, validatedPush } from "../rules/notifications";

type Tx = FirebaseFirestore.Transaction;
type Ref = FirebaseFirestore.DocumentReference;
const ms = (v: unknown) => (v as FirebaseFirestore.Timestamp).toMillis();

/** Demande en attente, examinée par l'instructeur désigné ou un admin, avant le départ. */
async function loadRequest(tx: Tx, ref: Ref, me: CallerProfile, now: number) {
  const f = await loadFlight(tx, ref);
  if (f.get("status") !== "demande") {
    throw new HttpsError("failed-precondition", "Ce vol n'est pas une demande en attente.");
  }
  if (!me.isAdmin && f.get("instructorUid") !== me.uid) {
    throw new HttpsError("permission-denied", "Réservé à l'instructeur désigné ou à un admin.");
  }
  if (ms(f.get("start")) <= now) {
    throw new HttpsError("failed-precondition", "Demande expirée : l'heure de départ est passée.");
  }
  return f;
}

export async function validateFlight(caller: Caller | undefined, data: unknown): Promise<void> {
  const db = admin.firestore();
  const me = await requireActiveUser(db, caller);
  const { flightId, changes } = asInvalid(() => validateReviewChanges(data));
  const now = Date.now();
  const ref = db.collection("flights").doc(flightId);

  const modified = await db.runTransaction(async (tx) => {
    const f = await loadRequest(tx, ref, me, now);
    const input: FlightInput = {
      start: changes.start ?? ms(f.get("start")),
      end: changes.end ?? ms(f.get("end")),
      destination: changes.destination ?? (f.get("destination") as string),
      aircraftId: changes.aircraftId ?? (f.get("aircraftId") as string),
      crew: f.get("crew") as string[],
      passengers: (f.get("passengers") as string[] | undefined) ?? [],
      pricingMode: changes.pricingMode,
      instruction: changes.instruction ?? (f.get("instruction") === true),
      baptism: false,
    };
    // Le baptême se lit dans le mode du vol ; sans passager il n'existe pas.
    input.baptism = input.passengers.length > 0 &&
      (changes.baptism ?? (f.get("pricingMode") === "baptism"));
    if (changes.baptism && input.passengers.length === 0) {
      throw new HttpsError("invalid-argument",
        "Baptême de l'air réservé à un vol avec un passager sans compte.");
    }
    asInvalid(() => checkDuration(input.start, input.end));
    asInvalid(() => checkHorizon(input.start, now));
    if (input.start <= now) throw new HttpsError("failed-precondition", "L'heure de départ est passée.");
    const instructorUid = (f.get("instructorUid") as string | null | undefined) ?? null;
    const p = await planFlight(tx, db, {
      id: ref.id, input, mayChoose: true,
      previousMode: f.get("pricingMode") as PricingMode,
      existingSnapshot: (f.get("pricingSnapshot") as Pricing | null | undefined) ?? null,
      previousStatus: f.get("status") as string,
      decide: () => ({ ok: true, status: "valide", instructorUid }),
    });
    touchLocks(tx, p.locks);
    tx.update(ref, p.fields);
    // « Avec modifications » : horaire, destination ou appareil changés.
    return input.start !== ms(f.get("start")) || input.end !== ms(f.get("end")) ||
      input.destination !== f.get("destination") || input.aircraftId !== f.get("aircraftId");
  });
  await notifyFlight(db, flightId, (f, names) => validatedPush(f, names, me.uid, modified));
}

export async function refuseFlight(caller: Caller | undefined, data: unknown): Promise<void> {
  const db = admin.firestore();
  const me = await requireActiveUser(db, caller);
  const { flightId, reason } = asInvalid(() => validateRefusal(data));
  const ref = db.collection("flights").doc(flightId);
  await db.runTransaction(async (tx) => {
    await loadRequest(tx, ref, me, Date.now());
    tx.update(ref, {
      status: "refuse", refusalReason: reason,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  await notifyFlight(db, flightId, (f, names) => refusedPush(f, names, me.uid, reason));
}

export async function cancelFlight(caller: Caller | undefined, data: unknown): Promise<void> {
  const db = admin.firestore();
  const me = await requireActiveUser(db, caller);
  const flightId = asInvalid(() => validateFlightId(data));
  const ref = db.collection("flights").doc(flightId);
  const status = await db.runTransaction(async (tx) => {
    const f = await loadFlight(tx, ref);
    if (!me.isAdmin && f.get("createdBy") !== me.uid && f.get("instructorUid") !== me.uid) {
      throw new HttpsError("permission-denied",
        "Seuls le créateur, l'instructeur désigné ou un admin peuvent annuler ce vol.");
    }
    assertNotStarted(f, Date.now());
    // Suppression logique uniquement (contrat AppGAP).
    tx.update(ref, { deleted: true, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    return f.get("status") as string;
  });
  // Spec §6.1 : seule l'annulation d'un vol validé est notifiée.
  if (status === "valide") {
    await notifyFlight(db, flightId, (f, names) => cancelledPush(f, names, me.uid));
  }
}

export const validateFlightFn = onCall((req) => validateFlight(req.auth as Caller | undefined, req.data));
export const refuseFlightFn = onCall((req) => refuseFlight(req.auth as Caller | undefined, req.data));
export const cancelFlightFn = onCall((req) => cancelFlight(req.auth as Caller | undefined, req.data));
