// Clôture d'un vol (spec §4.3) : bilan facturé sur tarifs figés, débit du
// compte débité et historique dans la même transaction (règle absolue).
// N'utilise pas `loadFlight` (core.ts) : celui-ci refuse un vol déjà clôturé
// avec un autre message, et ne vérifie pas le statut `valide`.
import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, requireActiveUser } from "../auth/guards";
import { asInvalid } from "../common/errors";
import { postMovement } from "../finance/ledger";
import { readPricing } from "../finance/pricing-store";
import { closingBill, Pricing, toCategory } from "../rules/pricing";
import { isOnOrBeforeClubToday } from "../rules/club-day";
import { touchLocks } from "./core";
import { validateClosing } from "./validation";

type Tx = FirebaseFirestore.Transaction;
type Ref = FirebaseFirestore.DocumentReference;
type Snap = FirebaseFirestore.DocumentSnapshot;
const { FieldValue } = admin.firestore;

async function loadClosable(tx: Tx, ref: Ref): Promise<Snap> {
  const f = await tx.get(ref);
  if (!f.exists || f.get("deleted") === true) throw new HttpsError("not-found", "Vol introuvable.");
  if (f.get("isClosed") === true) throw new HttpsError("failed-precondition", "Ce vol est déjà clôturé.");
  if (f.get("status") !== "valide") {
    throw new HttpsError("failed-precondition", "Ce vol n'est pas validé.");
  }
  return f;
}

export interface CloseResult { billedAmount: number; billedTo: "account" | "off_app" }

export async function closeFlight(caller: Caller | undefined, data: unknown): Promise<CloseResult> {
  const db = admin.firestore();
  const me = await requireActiveUser(db, caller);
  const { flightId, actualMinutes, shortFlightAmount, customAmount } = asInvalid(() => validateClosing(data));
  const now = Date.now();
  const ref = db.collection("flights").doc(flightId);

  return db.runTransaction(async (tx) => {
    const f = await loadClosable(tx, ref);
    const crew = (f.get("crew") as string[] | undefined) ?? [];
    if (!me.isAdmin && !crew.includes(me.uid)) {
      throw new HttpsError("permission-denied", "Réservé à l'équipage ou à un admin.");
    }
    if (!isOnOrBeforeClubToday((f.get("start") as FirebaseFirestore.Timestamp).toMillis(), now)) {
      throw new HttpsError("failed-precondition", "Le vol n'a pas encore eu lieu.");
    }

    // 1. Le vol (ci-dessus), le compte débité, son verrou, puis les tarifs.
    // payerUid de repli (spec §4.2, payerOf) : au cas où un vol ancien ne l'aurait pas encore.
    const payerUid = (f.get("payerUid") as string | undefined) ?? crew[0];
    const payerRef = db.collection("users").doc(payerUid);
    const payerSnap = await tx.get(payerRef);
    if (!payerSnap.exists) throw new HttpsError("not-found", "Compte débité introuvable.");
    const lockRef = db.collection("flightLocks").doc(`user_${payerUid}`);
    await tx.get(lockRef);
    const snapshot = (f.get("pricingSnapshot") as Pricing | null | undefined) ?? null;
    const pricing = snapshot ?? await readPricing(tx, db);

    // 2. Facturation (tarifs figés si pricingSnapshot, courants sinon, décision 3).
    const passengers = (f.get("passengers") as string[] | undefined) ?? [];
    let bill;
    try {
      bill = closingBill({
        mode: f.get("pricingMode") as "standard" | "fuel_only",
        actualMinutes,
        category: toCategory(payerSnap.get("category")),
        pricing,
        shortFlightAmount,
        customAmount,
        hasPassenger: passengers.length > 0,
      });
    } catch (e) {
      throw new HttpsError("invalid-argument", (e as Error).message);
    }

    // 3. Débit (aucun mouvement pour un vol facturé hors app).
    if (bill.billedTo === "account") {
      postMovement(tx, db, {
        uid: payerUid,
        amount: -bill.billedAmount,
        type: "flight",
        reason: "Vol",
        flightId: ref.id,
        by: me.uid,
        currentBalance: (payerSnap.get("balance") as number | undefined) ?? 0,
      });
    }
    touchLocks(tx, [lockRef]);

    // 4. Clôture du vol.
    tx.update(ref, {
      isClosed: true,
      actualFlightMinutes: actualMinutes,
      closedBy: me.uid,
      closedAt: FieldValue.serverTimestamp(),
      billedAmount: bill.billedAmount,
      billedTo: bill.billedTo,
      customAmount,
      shortFlightAmount,
      pricingMode: bill.pricingMode,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return { billedAmount: bill.billedAmount, billedTo: bill.billedTo };
  });
}

export const closeFlightFn = onCall((req) => closeFlight(req.auth as Caller | undefined, req.data));
