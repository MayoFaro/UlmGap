// Clôture d'un vol (spec §4.3) : bilan facturé sur tarifs figés, débit du
// compte débité et historique dans la même transaction (règle absolue),
// et carburant (spec §9) : cuve et crédit « bidon perso » (spec §13.2).
// N'utilise pas `loadFlight` (core.ts) : celui-ci refuse un vol déjà clôturé
// avec un autre message, et ne vérifie pas le statut `valide`.
import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, requireActiveUser } from "../auth/guards";
import { asInvalid } from "../common/errors";
import { postMovement } from "../finance/ledger";
import { readPricing } from "../finance/pricing-store";
import { postTankMovement, readTank } from "../finance/tank-ledger";
import { BaptismTier, BilledTo, closingBill, instructionCreditDue, Pricing, pricingWithDefaults, toCategory } from "../rules/pricing";
import { notifyMovements, WrittenMovement } from "../notify/movements";
import { isOnOrBeforeClubToday } from "../rules/club-day";
import { closingEnd } from "../rules/closing";
import { becomesFuelSource } from "../rules/fuel";
import { clubDayString } from "../rules/cash";
import { supplyCredit } from "../rules/tank";
import type { Profile } from "../admin/validation";
import { touchLocks } from "./core";
import { SUPPLIER_NOT_IN_CREW, validateClosing } from "./validation";

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

export interface CloseResult { billedAmount: number; billedTo: BilledTo }

export async function closeFlight(caller: Caller | undefined, data: unknown): Promise<CloseResult> {
  const db = admin.firestore();
  const me = await requireActiveUser(db, caller);
  const { flightId, actualMinutes, shortFlightAmount, customAmount, landings, waterLandings,
    fuelStartExpected, fuelStart, fuelFromTank, fuelFromPersonal, fuelSupplierUid, fuelAdded, fuelEnd } =
    asInvalid(() => validateClosing(data));
  const now = Date.now();
  const ref = db.collection("flights").doc(flightId);

  const { result, written } = await db.runTransaction(async (tx) => {
    const f = await loadClosable(tx, ref);
    const crew = (f.get("crew") as string[] | undefined) ?? [];
    if (!me.isAdmin && !crew.includes(me.uid)) {
      throw new HttpsError("permission-denied", "Réservé à l'équipage ou à un admin.");
    }
    // Spec §13.2 : le pilote qui a fourni le carburant est dans l'équipage.
    if (fuelSupplierUid !== null && !crew.includes(fuelSupplierUid)) {
      throw new HttpsError("invalid-argument", SUPPLIER_NOT_IN_CREW);
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
    // Plan 13 : le prix du litre (bidon perso) est toujours le tarif courant.
    const current = snapshot === null || fuelFromPersonal > 0 ? await readPricing(tx, db) : null;
    const pricing = pricingWithDefaults(snapshot ?? current!);

    // Plan 8 (spec §10.1) : équipage lu avant toute écriture, pour le crédit
    // d'instruction ; le verrou de l'instructeur, s'il n'est pas le payeur.
    const crewSnaps = await tx.getAll(...crew.map((u) => db.collection("users").doc(u)));
    const people = crewSnaps.map((s) => ({
      uid: s.id, profile: (s.get("profile") as Profile | undefined) ?? null,
    }));
    // Spec §12.2 : jamais de crédit d'instruction pour un vol technique.
    const mode = f.get("pricingMode") as "standard" | "fuel_only" | "baptism" | "technical";
    const credit = instructionCreditDue({
      instruction: mode !== "technical" && f.get("instruction") === true, actualMinutes, crew: people, pricing,
    });
    // Plan 13 (spec §13.2) : crédit « carburant fourni » au tarif courant.
    const supply = fuelSupplierUid !== null
      ? { uid: fuelSupplierUid, amount: supplyCredit(fuelFromPersonal, current!.fuelLiterPrice) } : null;
    // Un verrou par compte crédité autre que le payeur (lu avant toute écriture).
    const extraLocks = [...new Set([credit?.uid, supply?.uid])]
      .filter((u): u is string => !!u && u !== payerUid)
      .map((u) => db.collection("flightLocks").doc(`user_${u}`));
    if (extraLocks.length > 0) await tx.getAll(...extraLocks);
    const tank = fuelFromTank > 0 ? await readTank(tx, db) : null;
    // Soldes enchaînés : un même compte peut être débité puis crédité.
    const balances = new Map<string, number>(
      crewSnaps.map((s) => [s.id, (s.get("balance") as number | undefined) ?? 0]));

    // 2. Facturation (tarifs figés si pricingSnapshot, courants sinon, décision 3).
    const passengers = (f.get("passengers") as string[] | undefined) ?? [];
    let bill;
    try {
      bill = closingBill({
        mode,
        actualMinutes,
        category: toCategory(payerSnap.get("category")),
        pricing,
        shortFlightAmount,
        customAmount,
        hasPassenger: passengers.length > 0,
        baptismTier: (f.get("baptismTier") as BaptismTier | null | undefined) ?? null,
      });
    } catch (e) {
      throw new HttpsError("invalid-argument", (e as Error).message);
    }

    // 3. Débit (aucun mouvement pour un vol facturé hors app ou à l'association).
    balances.set(payerUid, (payerSnap.get("balance") as number | undefined) ?? 0);
    if (bill.billedTo === "account") {
      balances.set(payerUid, postMovement(tx, db, {
        uid: payerUid,
        amount: -bill.billedAmount,
        type: "flight",
        reason: "Vol",
        flightId: ref.id,
        by: me.uid,
        currentBalance: balances.get(payerUid)!,
      }));
    }
    touchLocks(tx, [lockRef, ...extraLocks]);

    // 3 bis. Crédits d'instruction puis de carburant fourni, enchaînés après
    // le débit (un même pilote peut être payeur, instructeur et fournisseur).
    const written: WrittenMovement[] = [];
    const credits = [
      ...(credit ? [{ ...credit, type: "instruction" as const, reason: "Crédit instruction" }] : []),
      ...(supply && supply.amount > 0
        ? [{ ...supply, type: "fuel_supply" as const, reason: "Carburant fourni (bidon perso)" }] : []),
    ];
    for (const c of credits) {
      const balanceAfter = postMovement(tx, db, {
        uid: c.uid,
        amount: c.amount,
        type: c.type,
        reason: c.reason,
        flightId: ref.id,
        by: me.uid,
        currentBalance: balances.get(c.uid) ?? 0,
      });
      balances.set(c.uid, balanceAfter);
      written.push({ uid: c.uid, amount: c.amount, balanceAfter, type: c.type });
    }

    // 3 ter. Carburant pris à la cuve (spec §13.2), daté du jour du vol.
    if (tank) {
      postTankMovement(tx, db, {
        kind: "flight",
        liters: -fuelFromTank,
        date: clubDayString(startMs),
        flightId: ref.id,
        aircraftId: aircraftRef.id,
        cashMovementId: null,
        measuredLiters: null,
        technical: mode === "technical",
        note: null,
        by: me.uid,
        currentLiters: tank.liters,
      });
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
      fuelFromTankLiters: fuelFromTank,
      fuelFromPersonalLiters: fuelFromPersonal,
      fuelSupplierUid,
      fuelSupplyCredit: supply?.amount ?? 0,
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
  await notifyMovements(db, me.uid, written);
  return result;
}

export const closeFlightFn = onCall((req) => closeFlight(req.auth as Caller | undefined, req.data));
