// Correction et suppression admin, à tout moment (spec §4.5, décisions du
// contrôleur). Sur un vol clôturé, la régularisation des soldes est
// automatique : transactions `flight_adjustment` dans la même transaction
// Firestore que la mise à jour du vol (règle absolue).
import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, requireAdmin } from "../auth/guards";
import { asInvalid } from "../common/errors";
import { postMovement } from "../finance/ledger";
import { designatedInstructor, PricingMode } from "../rules/flights";
import {
  adjustments, closingBill, computedCost, instructionAdjustments, instructionCreditDue, Pricing,
  pricingWithDefaults, toCategory,
} from "../rules/pricing";
import type { Profile } from "../admin/validation";
import { planFlight, touchLocks } from "./core";
import { checkHorizon, checkLandingsTotal, validateAdminUpdate, validateFlightId } from "./validation";
import { closingEnd } from "../rules/closing";
import { notifyFlight } from "../notify/flight-info";
import { notifyMovements, WrittenMovement } from "../notify/movements";
import { cancelledPush } from "../rules/notifications";

type Db = FirebaseFirestore.Firestore;
type Tx = FirebaseFirestore.Transaction;
type Ref = FirebaseFirestore.DocumentReference;
type Snap = FirebaseFirestore.DocumentSnapshot;
type BilledTo = "account" | "off_app" | null;
const { FieldValue } = admin.firestore;

/** Vol existant et non supprimé, qu'il soit clôturé ou non. */
async function loadAny(tx: Tx, ref: Ref): Promise<Snap> {
  const f = await tx.get(ref);
  if (!f.exists || f.get("deleted") === true) throw new HttpsError("not-found", "Vol introuvable.");
  return f;
}

/** Payeur d'un vol (repli sur crew[0] pour un vol ancien, spec §4.2). */
const payerUidOf = (f: Snap): string | null =>
  (f.get("payerUid") as string | undefined) ?? ((f.get("crew") as string[] | undefined) ?? [])[0] ?? null;

/**
 * Lit les comptes `uids` et leurs verrous (avant toute écriture, cf.
 * postMovement) ; renvoie les comptes et les verrous à écrire.
 */
async function readAccounts(
  tx: Tx, db: Db, uids: string[],
): Promise<{ users: Map<string, Snap>; locks: Ref[] }> {
  const unique = [...new Set(uids)];
  const snaps = await tx.getAll(...unique.map((u) => db.collection("users").doc(u)));
  const users = new Map<string, Snap>();
  for (const s of snaps) {
    if (!s.exists) throw new HttpsError("not-found", "Compte débité introuvable.");
    users.set(s.id, s);
  }
  const locks = unique.map((u) => db.collection("flightLocks").doc(`user_${u}`));
  await tx.getAll(...locks);
  return { users, locks };
}

const balanceOf = (s: Snap | undefined) => (s?.get("balance") as number | undefined) ?? 0;

export async function adminUpdateFlight(caller: Caller | undefined, data: unknown): Promise<void> {
  const db = admin.firestore();
  await requireAdmin(db, caller);
  const by = caller!.uid;
  const v = asInvalid(() => validateAdminUpdate(data));
  asInvalid(() => checkHorizon(v.input.start, Date.now()));
  const ref = db.collection("flights").doc(v.flightId);

  const written = await db.runTransaction(async (tx): Promise<WrittenMovement[]> => {
    const f = await loadAny(tx, ref);
    const closed = f.get("isClosed") === true;
    const status = f.get("status") as string;
    if (status !== "demande" && status !== "valide") {
      throw new HttpsError("failed-precondition", "Un vol refusé ne peut pas être corrigé.");
    }
    if (!closed && (v.pricingMode === "custom" || v.actualMinutes !== undefined ||
        v.shortFlightAmount != null || v.customAmount != null ||
        v.landings !== undefined || v.waterLandings !== undefined ||
        v.fuelStart !== undefined || v.fuelAdded !== undefined || v.fuelEnd !== undefined)) {
      throw new HttpsError("failed-precondition", "Réservé aux vols clôturés.");
    }

    // Mode : celui demandé par l'admin est imposé ; un montant différent seul
    // vaut « custom » ; un vol « custom » le reste. Sinon, le mode est
    // recalculé (spec §4.1) : un vol carburant dont l'équipage n'est plus
    // tout GAP repasse en standard. Plan 8 : un baptême l'emporte (mode
    // imposé par planFlight).
    const previousMode = f.get("pricingMode") as PricingMode;
    const mode: PricingMode | undefined = v.input.baptism ? undefined : v.pricingMode ??
      (v.customAmount != null || previousMode === "custom" ? "custom" : undefined);
    // Plan 4b : sur un vol clôturé, nombres fusionnés avec les valeurs
    // stockées (1 atterrissage pour un vol clôturé avant le plan 4b),
    // amerrissages réservés à un appareil amphibie, et fin allongée si la
    // durée réelle dépasse fin − début (conflits vérifiés par planFlight).
    const actualMinutes = v.actualMinutes ?? (f.get("actualFlightMinutes") as number);
    let landings = 0;
    let waterLandings = 0;
    let fuelAircraftRef: Ref | null = null;
    let input = v.input;
    if (closed) {
      landings = v.landings ?? (f.get("landings") as number | undefined) ?? 1;
      waterLandings = v.waterLandings ?? (f.get("waterLandings") as number | undefined) ?? 0;
      asInvalid(() => checkLandingsTotal(landings, waterLandings));
      if (waterLandings > 0) {
        const aircraft = await tx.get(db.collection("aircraft").doc(input.aircraftId));
        if (aircraft.get("amphibious") !== true) {
          throw new HttpsError("failed-precondition", "Cet appareil n'est pas amphibie.");
        }
      }
      // Plan 7 (spec §9.3) : le carburant actuel suit la correction si ce
      // vol en est la source et que son appareil ne change pas.
      if (v.fuelEnd !== undefined && input.aircraftId === f.get("aircraftId")) {
        const ref2 = db.collection("aircraft").doc(input.aircraftId);
        const ac = await tx.get(ref2);
        if (ac.exists && ac.get("fuelFlightId") === ref.id) fuelAircraftRef = ref2;
      }
      input = { ...input, end: closingEnd(input.start, input.end, actualMinutes) };
    }

    const createdBy = (f.get("createdBy") as string | undefined) ?? "";
    const p = await planFlight(tx, db, {
      id: ref.id, input, mayChoose: true,
      previousMode,
      forcedMode: mode === "custom" ? "standard" : mode,
      skipActiveChecks: true,
      skipCredit: closed,
      closed,
      existingSnapshot: (f.get("pricingSnapshot") as Pricing | null | undefined) ?? null,
      previousStatus: status,
      decide: (crew) => ({
        ok: true,
        status: status as "demande" | "valide",
        instructorUid: designatedInstructor(createdBy, crew),
      }),
    });

    if (!closed) {
      touchLocks(tx, p.locks);
      tx.update(ref, p.fields);
      return [];
    }

    // Vol clôturé : nouvelle facture (tarifs figés du vol, sinon courants,
    // via le pricingSnapshot rendu par planFlight ; appartenance du nouveau
    // compte débité).
    const oldPayer = payerUidOf(f);
    const newPayer = p.fields.payerUid as string;
    // Plan 8 (spec §10.1) : tarifs d'avant le plan 8 complétés ; crédit
    // d'instruction recalculé sur l'équipage corrigé (lu avant toute
    // écriture), régularisé par rapport au crédit déjà versé.
    const pricing = pricingWithDefaults(p.fields.pricingSnapshot as Pricing);
    const crewSnaps = await tx.getAll(...input.crew.map((u) => db.collection("users").doc(u)));
    const people = crewSnaps.map((s) => ({
      uid: s.id, profile: (s.get("profile") as Profile | undefined) ?? null,
    }));
    const credit = instructionCreditDue({
      instruction: input.instruction, actualMinutes, crew: people, pricing,
    });
    const instructionMoves = instructionAdjustments(
      {
        uid: (f.get("instructionCreditUid") as string | null | undefined) ?? null,
        amount: (f.get("instructionCreditAmount") as number | null | undefined) ?? 0,
      },
      credit ?? { uid: null, amount: 0 },
    );
    const accounts = await readAccounts(tx, db, [
      ...(oldPayer ? [oldPayer] : []), newPayer, ...instructionMoves.map((m) => m.uid),
    ]);
    const customAmount = mode === "custom"
      ? (v.customAmount !== undefined ? v.customAmount : (f.get("customAmount") as number | null) ?? null)
      : null;
    if (mode === "custom" && customAmount == null) {
      throw new HttpsError("invalid-argument", "Montant différent obligatoire en mode « montant différent ».");
    }
    const shortFlightAmount = v.shortFlightAmount !== undefined
      ? v.shortFlightAmount
      : (f.get("shortFlightAmount") as number | null | undefined) ?? null;
    const billMode = p.fields.pricingMode as "standard" | "fuel_only" | "baptism";
    const category = toCategory(accounts.users.get(newPayer)!.get("category"));
    let bill;
    try {
      bill = closingBill({
        mode: billMode,
        actualMinutes,
        category,
        pricing,
        shortFlightAmount,
        customAmount,
        hasPassenger: input.passengers.length > 0,
        baptismTier: input.baptism ? input.baptismTier : null,
      });
    } catch (e) {
      throw new HttpsError("invalid-argument", (e as Error).message);
    }

    // Régularisation (spec §4.5) : remboursement de l'ancien débit, débit du
    // nouveau, regroupés par compte, montants nuls omis.
    const moves = adjustments(
      {
        billedTo: (f.get("billedTo") as BilledTo | undefined) ?? null,
        payerUid: oldPayer,
        amount: (f.get("billedAmount") as number | null | undefined) ?? 0,
      },
      { billedTo: bill.billedTo, payerUid: newPayer, amount: bill.billedAmount },
    );
    // Soldes enchaînés : un compte peut recevoir une régularisation de vol
    // puis une d'instruction.
    const balances = new Map([...accounts.users].map(([uid, snap]) => [uid, balanceOf(snap)]));
    const posted: WrittenMovement[] = [];
    for (const m of moves) {
      const balanceAfter = postMovement(tx, db, {
        uid: m.uid, amount: m.amount, type: "flight_adjustment", reason: "Régularisation",
        flightId: ref.id, by, currentBalance: balances.get(m.uid)!,
      });
      balances.set(m.uid, balanceAfter);
      posted.push({ uid: m.uid, amount: m.amount, balanceAfter, type: "flight_adjustment" });
    }
    for (const m of instructionMoves) {
      const balanceAfter = postMovement(tx, db, {
        uid: m.uid, amount: m.amount, type: "instruction", reason: "Régularisation crédit instruction",
        flightId: ref.id, by, currentBalance: balances.get(m.uid)!,
      });
      balances.set(m.uid, balanceAfter);
      posted.push({ uid: m.uid, amount: m.amount, balanceAfter, type: "instruction" });
    }
    touchLocks(tx, [...p.locks, ...accounts.locks.filter((l) => !p.locks.some((k) => k.path === l.path))]);
    tx.update(ref, {
      ...p.fields,
      actualFlightMinutes: actualMinutes,
      landings,
      waterLandings,
      billedAmount: bill.billedAmount,
      billedTo: bill.billedTo,
      pricingMode: bill.pricingMode,
      customAmount,
      // Montant à facturer conservé seulement s'il sert (vol standard sous la
      // durée minimale), jamais périmé ; jamais pour un baptême.
      shortFlightAmount: billMode !== "baptism" && bill.pricingMode !== "custom" &&
        computedCost(billMode, actualMinutes, category, pricing) === null ? shortFlightAmount : null,
      instructionCreditUid: credit?.uid ?? null,
      instructionCreditAmount: credit?.amount ?? null,
      ...(v.fuelStart !== undefined ? { fuelStartLiters: v.fuelStart } : {}),
      ...(v.fuelAdded !== undefined ? { fuelAddedLiters: v.fuelAdded } : {}),
      ...(v.fuelEnd !== undefined ? { fuelEndLiters: v.fuelEnd } : {}),
    });
    if (fuelAircraftRef) {
      tx.update(fuelAircraftRef, { fuelLiters: v.fuelEnd, updatedAt: FieldValue.serverTimestamp() });
    }
    return posted;
  });
  await notifyMovements(db, by, written);
}

export async function adminDeleteFlight(caller: Caller | undefined, data: unknown): Promise<void> {
  const db = admin.firestore();
  await requireAdmin(db, caller);
  const by = caller!.uid;
  const flightId = asInvalid(() => validateFlightId(data));
  const ref = db.collection("flights").doc(flightId);

  const { cancelled, written } = await db.runTransaction(async (tx) => {
    const f = await loadAny(tx, ref);
    const written: WrittenMovement[] = [];
    const closed = f.get("isClosed") === true;
    // Remboursement d'un vol clôturé débité sur un compte ; plan 8 : reprise
    // du crédit d'instruction versé (comptes lus ensemble, avant écriture).
    const payer = payerUidOf(f);
    const refundPayer = closed && f.get("billedTo") === "account" && payer ? payer : null;
    // Crédit nul ou absent (crédit désactivé dans Tarifs) : rien à reprendre.
    const creditAmount = (f.get("instructionCreditAmount") as number | null | undefined) ?? 0;
    const creditUid = closed && creditAmount > 0
      ? (f.get("instructionCreditUid") as string | null | undefined) ?? null : null;
    const uids = [...(refundPayer ? [refundPayer] : []), ...(creditUid ? [creditUid] : [])];
    if (uids.length > 0) {
      const accounts = await readAccounts(tx, db, uids);
      const balances = new Map([...accounts.users].map(([uid, snap]) => [uid, balanceOf(snap)]));
      if (refundPayer) {
        const amount = f.get("billedAmount") as number;
        const balanceAfter = postMovement(tx, db, {
          uid: refundPayer, amount, type: "flight_adjustment",
          reason: "Annulation du vol", flightId: ref.id, by,
          currentBalance: balances.get(refundPayer)!,
        });
        balances.set(refundPayer, balanceAfter);
        written.push({ uid: refundPayer, amount, balanceAfter, type: "flight_adjustment" });
      }
      if (creditUid) {
        const amount = -creditAmount;
        const balanceAfter = postMovement(tx, db, {
          uid: creditUid, amount, type: "instruction",
          reason: "Régularisation crédit instruction", flightId: ref.id, by,
          currentBalance: balances.get(creditUid)!,
        });
        written.push({ uid: creditUid, amount, balanceAfter, type: "instruction" });
      }
      touchLocks(tx, accounts.locks);
    }
    // Suppression logique uniquement (contrat AppGAP).
    tx.update(ref, { deleted: true, updatedAt: FieldValue.serverTimestamp() });
    // Spec §6.1 : un vol validé non clôturé supprimé = vol annulé.
    return { cancelled: f.get("status") === "valide" && !closed, written };
  });
  if (cancelled) await notifyFlight(db, flightId, (f, names) => cancelledPush(f, names, by));
  if (written.length > 0) await notifyMovements(db, by, written);
}

export const adminUpdateFlightFn = onCall((req) =>
  adminUpdateFlight(req.auth as Caller | undefined, req.data));
export const adminDeleteFlightFn = onCall((req) =>
  adminDeleteFlight(req.auth as Caller | undefined, req.data));
