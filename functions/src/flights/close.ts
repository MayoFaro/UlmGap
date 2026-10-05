// Clôture d'un vol (spec §4.3) : bilan facturé sur tarifs figés, débit du
// compte débité et historique dans la même transaction (règle absolue),
// et carburant (spec §9).
// N'utilise pas `loadFlight` (core.ts) : celui-ci refuse un vol déjà clôturé
// avec un autre message, et ne vérifie pas le statut `valide`.
import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, requireActiveUser } from "../auth/guards";
import { asInvalid } from "../common/errors";
import { postMovement } from "../finance/ledger";
import { readPricing } from "../finance/pricing-store";
import { closingBill, instructionCreditDue, Pricing, pricingWithDefaults, toCategory } from "../rules/pricing";
import { notifyMovements, WrittenMovement } from "../notify/movements";
import { isOnOrBeforeClubToday } from "../rules/club-day";
import { closingEnd } from "../rules/closing";
import { becomesFuelSource } from "../rules/fuel";
import type { Profile } from "../admin/validation";
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
  const { flightId, actualMinutes, shortFlightAmount, customAmount, landings, waterLandings,
    fuelStartExpected, fuelStart, fuelAdded, fuelEnd } =
    asInvalid(() => validateClosing(data));
  const now = Date.now();
  const ref = db.collection("flights").doc(flightId);

  const { result, written } = await db.runTransaction(async (tx) => {
    const f = await loadClosable(tx, ref);
    const crew = (f.get("crew") as string[] | undefined) ?? [];
    if (!me.isAdmin && !crew.includes(me.uid)) {
      throw new HttpsError("permission-denied", "Réservé à l'équipage ou à un admin.");
    }
    const startMs = (f.get("start") as FirebaseFirestore.Timestamp).toMillis();
    if (!isOnOrBeforeClubToday(startMs, now)) {
      throw new HttpsError("failed-precondition", "Le vol n'a pas encore eu lieu.");
    }

    // Plan 4b : amerrissages réservés à un appareil amphibie. Plan 7 :
    // l'appareil est lu dans tous les cas (carburant actuel, spec §9.2).
    const aircraftRef = db.collection("aircraft").doc(f.get("aircraftId") as string);
    const aircraft = await tx.get(aircraftRef);
    if (waterLandings > 0 && aircraft.get("amphibious") !== true) {
      throw new HttpsError("failed-precondition", "Cet appareil n'est pas amphibie.");
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
    // Plan 8 : un snapshot d'avant le plan 8 n'a pas les nouveaux tarifs.
    const pricing = pricingWithDefaults(snapshot ?? await readPricing(tx, db));

    // Plan 8 (spec §10.1) : équipage lu avant toute écriture, pour le crédit
    // d'instruction ; le verrou de l'instructeur, s'il n'est pas le payeur.
    const crewSnaps = await tx.getAll(...crew.map((u) => db.collection("users").doc(u)));
    const people = crewSnaps.map((s) => ({
      uid: s.id, profile: (s.get("profile") as Profile | undefined) ?? null,
    }));
    const credit = instructionCreditDue({
      instruction: f.get("instruction") === true, actualMinutes, crew: people, pricing,
    });
    const creditLockRef = credit && credit.uid !== payerUid
      ? db.collection("flightLocks").doc(`user_${credit.uid}`) : null;
    if (creditLockRef) await tx.get(creditLockRef);
    const instructorBalance = credit
      ? (crewSnaps.find((s) => s.id === credit.uid)?.get("balance") as number | undefined) ?? 0
      : 0;

    // 2. Facturation (tarifs figés si pricingSnapshot, courants sinon, décision 3).
    const passengers = (f.get("passengers") as string[] | undefined) ?? [];
    let bill;
    try {
      bill = closingBill({
        mode: f.get("pricingMode") as "standard" | "fuel_only" | "baptism",
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
    let payerBalance = (payerSnap.get("balance") as number | undefined) ?? 0;
    if (bill.billedTo === "account") {
      payerBalance = postMovement(tx, db, {
        uid: payerUid,
        amount: -bill.billedAmount,
        type: "flight",
        reason: "Vol",
        flightId: ref.id,
        by: me.uid,
        currentBalance: payerBalance,
      });
    }
    touchLocks(tx, creditLockRef ? [lockRef, creditLockRef] : [lockRef]);

    // 3 bis. Crédit d'instruction, enchaîné après le débit si l'instructeur
    // est aussi le payeur.
    let written: WrittenMovement | null = null;
    if (credit) {
      const balanceAfter = postMovement(tx, db, {
        uid: credit.uid,
        amount: credit.amount,
        type: "instruction",
        reason: "Crédit instruction",
        flightId: ref.id,
        by: me.uid,
        currentBalance: credit.uid === payerUid ? payerBalance : instructorBalance,
      });
      written = { uid: credit.uid, amount: credit.amount, balanceAfter, type: "instruction" };
    }

    // 4. Clôture du vol.
    tx.update(ref, {
      isClosed: true,
      actualFlightMinutes: actualMinutes,
      landings,
      waterLandings,
      // Plan 4b, décision 4 : fin allongée si le vol réel a duré plus que prévu.
      end: admin.firestore.Timestamp.fromMillis(
        closingEnd(startMs, (f.get("end") as FirebaseFirestore.Timestamp).toMillis(), actualMinutes)),
      closedBy: me.uid,
      closedAt: FieldValue.serverTimestamp(),
      billedAmount: bill.billedAmount,
      billedTo: bill.billedTo,
      customAmount,
      shortFlightAmount,
      pricingMode: bill.pricingMode,
      instructionCreditUid: credit?.uid ?? null,
      instructionCreditAmount: credit?.amount ?? null,
      fuelStartExpectedLiters: fuelStartExpected,
      fuelStartLiters: fuelStart,
      fuelAddedLiters: fuelAdded,
      fuelEndLiters: fuelEnd,
      updatedAt: FieldValue.serverTimestamp(),
    });

    // 5. Carburant actuel de l'appareil (spec §9.2) : seulement si ce vol
    // est le plus récent à avoir déclaré son carburant.
    const sourceStart = aircraft.get("fuelFlightStart") as FirebaseFirestore.Timestamp | undefined;
    if (aircraft.exists && becomesFuelSource(startMs, sourceStart?.toMillis() ?? null)) {
      tx.update(aircraftRef, {
        fuelLiters: fuelEnd,
        fuelFlightId: ref.id,
        fuelFlightStart: f.get("start"),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    return { result: { billedAmount: bill.billedAmount, billedTo: bill.billedTo }, written };
  });
  if (written) await notifyMovements(db, me.uid, [written]);
  return result;
}

export const closeFlightFn = onCall((req) => closeFlight(req.auth as Caller | undefined, req.data));
