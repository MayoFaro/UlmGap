import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, CallerProfile, requireActiveUser } from "../auth/guards";
import { asInvalid } from "../common/errors";
import { PricingMode, checkPayer, decideStatus } from "../rules/flights";
import type { Pricing } from "../rules/pricing";
import { assertNotStarted, loadFlight, planFlight, touchLocks } from "./core";
import { checkHorizon, validateFlightId, validateFlightInput } from "./validation";
import { notifyFlight } from "../notify/flight-info";
import { requestPush } from "../rules/notifications";

/** Spec §4.1 : un instructeur ou un admin choisit « carburant seulement ». */
const mayChoose = (me: CallerProfile) => me.isAdmin || me.profile === "instructeur";

function assertFuture(start: number, now: number): void {
  if (start <= now) throw new HttpsError("failed-precondition", "L'heure de départ est passée.");
}

export async function createFlight(
  caller: Caller | undefined, data: unknown,
): Promise<{ id: string; status: string }> {
  const db = admin.firestore();
  const me = await requireActiveUser(db, caller);
  const input = asInvalid(() => validateFlightInput(data));
  const now = Date.now();
  asInvalid(() => checkHorizon(input.start, now));
  // Seul un admin saisit après coup un vol passé (vol oublié).
  if (!me.isAdmin) assertFuture(input.start, now);
  const payerError = checkPayer(me, input.crew);
  if (payerError) throw new HttpsError("permission-denied", payerError);
  const ref = db.collection("flights").doc();

  const status = await db.runTransaction(async (tx) => {
    const p = await planFlight(tx, db, {
      id: ref.id, input, mayChoose: mayChoose(me),
      decide: (crew) => decideStatus(me, crew, input.passengers.length),
    });
    touchLocks(tx, p.locks);
    tx.create(ref, {
      ...p.fields,
      createdBy: me.uid,
      refusalReason: null,
      customAmount: null,
      shortFlightAmount: null,
      isClosed: false,
      actualFlightMinutes: null,
      closedBy: null,
      closedAt: null,
      billedAmount: null,
      billedTo: null,
      reminderGen: 0,
      deleted: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return p.status;
  });
  if (status === "demande") {
    await notifyFlight(db, ref.id, (f, names) => requestPush(f, names, me.uid, false));
  }
  return { id: ref.id, status };
}

export async function updateFlight(caller: Caller | undefined, data: unknown): Promise<{ status: string }> {
  const db = admin.firestore();
  const me = await requireActiveUser(db, caller);
  const flightId = asInvalid(() => validateFlightId(data));
  const input = asInvalid(() => validateFlightInput(data));
  const now = Date.now();
  asInvalid(() => checkHorizon(input.start, now));
  assertFuture(input.start, now);
  const payerError = checkPayer(me, input.crew);
  if (payerError) throw new HttpsError("permission-denied", payerError);
  const ref = db.collection("flights").doc(flightId);

  const status = await db.runTransaction(async (tx) => {
    const f = await loadFlight(tx, ref);
    if (f.get("createdBy") !== me.uid) {
      throw new HttpsError("permission-denied", "Seul le créateur peut modifier ce vol.");
    }
    assertNotStarted(f, now);
    const p = await planFlight(tx, db, {
      id: ref.id, input, mayChoose: mayChoose(me),
      // Mode conservé seulement si aucun passager ne l'imposait (décision 2b).
      previousMode: ((f.get("passengers") as string[] | undefined) ?? []).length === 0
        ? (f.get("pricingMode") as PricingMode)
        : undefined,
      existingSnapshot: (f.get("pricingSnapshot") as Pricing | null | undefined) ?? null,
      previousStatus: f.get("status") as string,
      decide: (crew) => decideStatus(me, crew, input.passengers.length),
    });
    touchLocks(tx, p.locks);
    tx.update(ref, { ...p.fields, refusalReason: null });
    return p.status;
  });
  if (status === "demande") {
    await notifyFlight(db, ref.id, (f, names) => requestPush(f, names, me.uid, true));
  }
  return { status };
}

export const createFlightFn = onCall((req) => createFlight(req.auth as Caller | undefined, req.data));
export const updateFlightFn = onCall((req) => updateFlight(req.auth as Caller | undefined, req.data));
