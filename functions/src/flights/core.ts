// Lectures en transaction, contrôles communs (spec §3.4), conflits (§3.5) et
// verrous. Toutes les lectures précèdent les écritures (règle des transactions).
import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import type { Profile } from "../admin/validation";
import { asInvalid } from "../common/errors";
import { readPricing } from "../finance/pricing-store";
import {
  Decision, ExistingFlight, FlightStatus, PricingMode, conflictCause, findConflict, isInstructionEligible,
  isPlanning, payerOf, resolvePricingMode,
} from "../rules/flights";
import {
  availableCredit, estimatedCost, formatFcfa, Pricing, pricingWithDefaults, toCategory,
} from "../rules/pricing";
import { checkMinDuration, type FlightInput } from "./validation";

type Db = FirebaseFirestore.Firestore;
type Tx = FirebaseFirestore.Transaction;
type Ref = FirebaseFirestore.DocumentReference;
type Snap = FirebaseFirestore.DocumentSnapshot;
const { Timestamp, FieldValue } = admin.firestore;

export interface CrewInfo {
  uid: string;
  shortName: string;
  profile: Profile | null;
  category: string;
  active: boolean;
  balance: number;
}

export interface PlanArgs {
  id: string;
  input: FlightInput;
  decide: (crew: CrewInfo[]) => Decision;
  mayChoose: boolean;
  previousMode?: PricingMode;
  /** Snapshot existant du vol (édition/validation), pour la décision de gel (spec, ctrl.). */
  existingSnapshot?: Pricing | null;
  previousStatus?: string;
  /** Correction admin : ni comptes ni appareils actifs contrôlés. */
  skipActiveChecks?: boolean;
  /** Correction admin d'un vol clôturé : la régularisation remplace le contrôle du crédit. */
  skipCredit?: boolean;
  /** Vol clôturé (correction admin) : conduite, aucun contrôle de conflit. */
  closed?: boolean;
  /** Correction admin : mode imposé explicitement par l'admin (resolvePricingMode non appliqué). */
  forcedMode?: "standard" | "fuel_only";
}

export interface Planned {
  status: "demande" | "valide";
  fields: Record<string, unknown>;
  locks: Ref[];
}

export async function loadFlight(tx: Tx, ref: Ref): Promise<Snap> {
  const f = await tx.get(ref);
  if (!f.exists || f.get("deleted") === true) throw new HttpsError("not-found", "Vol introuvable.");
  if (f.get("isClosed") === true) throw new HttpsError("failed-precondition", "Ce vol est clôturé.");
  return f;
}

export function assertNotStarted(f: Snap, now: number): void {
  if ((f.get("start") as FirebaseFirestore.Timestamp).toMillis() <= now) {
    throw new HttpsError("failed-precondition", "Le vol a déjà commencé.");
  }
}

async function loadCrew(tx: Tx, db: Db, uids: string[]): Promise<CrewInfo[]> {
  const snaps = await tx.getAll(...uids.map((u) => db.collection("users").doc(u)));
  return snaps.map((s) => {
    if (!s.exists) throw new HttpsError("not-found", "Membre d'équipage introuvable.");
    return {
      uid: s.id,
      shortName: (s.get("shortName") as string | undefined) ?? s.id,
      profile: (s.get("profile") as Profile | null | undefined) ?? null,
      category: (s.get("category") as string | undefined) ?? "EXT",
      active: s.get("active") === true,
      balance: (s.get("balance") as number | undefined) ?? 0,
    };
  });
}

async function loadAircraft(
  tx: Tx, db: Db, id: string, checkActive: boolean,
): Promise<{ id: string; registration: string }> {
  const s = await tx.get(db.collection("aircraft").doc(id));
  if (!s.exists) throw new HttpsError("not-found", "Appareil introuvable.");
  const registration = (s.get("registration") as string | undefined) ?? "";
  if (checkActive && s.get("active") !== true) {
    throw new HttpsError("failed-precondition", `L'appareil ${registration} n'est plus actif.`);
  }
  return { id, registration };
}

/**
 * Verrous (un document par appareil et par personne) : lus ici, écrits par
 * touchLocks. Deux transactions qui réservent le même appareil ou la même
 * personne se sérialisent, et la seconde voit le vol de la première.
 */
async function readLocks(tx: Tx, db: Db, aircraftId: string, crew: string[]): Promise<Ref[]> {
  const col = db.collection("flightLocks");
  const refs = [col.doc(`aircraft_${aircraftId}`), ...crew.map((u) => col.doc(`user_${u}`))];
  await tx.getAll(...refs);
  return refs;
}

export function touchLocks(tx: Tx, locks: Ref[]): void {
  for (const l of locks) tx.set(l, { at: FieldValue.serverTimestamp() });
}

async function assertNoConflict(
  tx: Tx, db: Db, slot: { id: string; start: number; end: number; aircraftId: string; crew: string[] },
): Promise<void> {
  // Un seul filtre d'inégalité (index simple automatique) ; le reste en mémoire.
  const snap = await tx.get(db.collection("flights").where("end", ">", Timestamp.fromMillis(slot.start)));
  const others: ExistingFlight[] = snap.docs.map((d) => ({
    id: d.id,
    start: (d.get("start") as FirebaseFirestore.Timestamp).toMillis(),
    end: (d.get("end") as FirebaseFirestore.Timestamp).toMillis(),
    aircraftId: d.get("aircraftId") as string,
    crew: (d.get("crew") as string[] | undefined) ?? [],
    status: d.get("status") as FlightStatus,
    deleted: d.get("deleted") === true,
    closed: d.get("isClosed") === true,
  }));
  const c = findConflict(slot, others);
  if (!c) return;
  const doc = snap.docs.find((d) => d.id === c.id)!;
  throw new HttpsError("failed-precondition", "Conflit avec un autre vol validé.", {
    conflict: {
      start: c.start, end: c.end,
      aircraft: (doc.get("aircraft") as string | undefined) ?? "",
      crew: c.crew,
      passengers: (doc.get("passengers") as string[] | undefined) ?? [],
      ...conflictCause(slot, c),
    },
  });
}

/**
 * Contrôle du crédit (décision 1, spec §4.4) : le crédit disponible du compte
 * débité doit couvrir le coût estimé du vol en cours, qu'il devienne une
 * demande ou un vol valide. Le verrou `flightLocks/user_<payeur>` est lu (et
 * ajouté à `locks` s'il n'y est pas déjà) pour sérialiser deux contrôles sur
 * le même compte.
 *
 * `ownPricing` sert au coût du vol en cours : les tarifs courants, sauf s'il
 * reste `valide` (un `pricingSnapshot` existant est conservé), auquel cas
 * c'est le même snapshot figé qui le facturera (règle du contrôleur, task 3
 * fix). `fallbackPricing` (toujours les tarifs courants) sert de repli pour
 * les *autres* vols du compte qui n'ont pas encore de `pricingSnapshot`
 * (vols validés avant le plan 3, décision 3).
 */
async function checkCredit(
  tx: Tx, db: Db, locks: Ref[],
  a: {
    id: string; payerUid: string; category: string; pricingMode: "standard" | "fuel_only";
    plannedMinutes: number; balance: number; shortName: string;
    ownPricing: Pricing; fallbackPricing: Pricing;
  },
): Promise<Ref[]> {
  const lockRef = db.collection("flightLocks").doc(`user_${a.payerUid}`);
  let out = locks;
  if (!out.some((l) => l.path === lockRef.path)) {
    await tx.get(lockRef);
    out = [...out, lockRef];
  }
  const category = toCategory(a.category);
  // Égalités seules (pas d'index composite) : on ne lit ni ne verrouille
  // l'historique des vols clôturés (createFlight écrit toujours isClosed).
  const snap = await tx.get(db.collection("flights")
    .where("payerUid", "==", a.payerUid)
    .where("isClosed", "==", false));
  const otherCosts = snap.docs
    .filter((d) =>
      d.id !== a.id &&
      d.get("status") === "valide" &&
      d.get("isClosed") !== true &&
      d.get("deleted") !== true &&
      (d.get("pricingMode") === "standard" || d.get("pricingMode") === "fuel_only"))
    .map((d) => {
      const start = (d.get("start") as FirebaseFirestore.Timestamp).toMillis();
      const end = (d.get("end") as FirebaseFirestore.Timestamp).toMillis();
      // Ancien snapshot sans toleranceMinutes : complété par pricingWithDefaults.
      const snapshot = d.get("pricingSnapshot") as Partial<Pricing> | null | undefined;
      const otherPricing = snapshot ? pricingWithDefaults(snapshot) : a.fallbackPricing;
      return estimatedCost(
        d.get("pricingMode") as "standard" | "fuel_only", (end - start) / 60_000, category, otherPricing,
      );
    });
  const available = availableCredit(a.balance, otherCosts);
  const cost = estimatedCost(a.pricingMode, a.plannedMinutes, category, a.ownPricing);
  if (available < cost) {
    const missing = cost - available;
    throw new HttpsError("failed-precondition",
      `Crédit insuffisant pour ${a.shortName} : il manque ${formatFcfa(missing)}.`,
      { credit: { missing, available, cost } });
  }
  return out;
}

/**
 * Contrôles communs, décision de statut, mode de tarification, payeur et,
 * si le vol devient ou reste valide, conflits et verrous.
 */
export async function planFlight(tx: Tx, db: Db, a: PlanArgs): Promise<Planned> {
  const crew = await loadCrew(tx, db, a.input.crew);
  const aircraft = await loadAircraft(tx, db, a.input.aircraftId, !a.skipActiveChecks);
  const pricing = await readPricing(tx, db);
  asInvalid(() => checkMinDuration(a.input.start, a.input.end, pricing.minPlannedMinutes));
  const off = a.skipActiveChecks ? undefined : crew.find((c) => !c.active);
  if (off) throw new HttpsError("failed-precondition", `${off.shortName} n'est plus actif.`);

  const d = a.decide(crew);
  if (!d.ok) throw new HttpsError("permission-denied", d.reason);

  // Spec §10.1 : vol d'instruction réservé à un instructeur + un autre membre.
  if (a.input.instruction && !isInstructionEligible(crew)) {
    throw new HttpsError("invalid-argument",
      "Vol d'instruction : il faut un instructeur et un autre membre avec compte.");
  }

  const pricingMode: PricingMode = a.input.baptism ? "baptism" : (a.forcedMode ?? resolvePricingMode({
    allGap: crew.every((c) => c.category === "GAP"),
    hasPassenger: a.input.passengers.length > 0,
    mayChoose: a.mayChoose,
    requested: a.input.pricingMode,
    previous: a.previousMode,
  }));

  let locks: Ref[] = [];
  if (d.status === "valide") {
    locks = await readLocks(tx, db, aircraft.id, a.input.crew);
    // Révision du 2026-10-01 : conflits contrôlés en planification seulement
    // (vol à venir non clôturé), jamais en conduite.
    if (isPlanning(a.input.start, Date.now(), a.closed === true)) {
      await assertNoConflict(tx, db, {
        id: a.id, start: a.input.start, end: a.input.end, aircraftId: aircraft.id, crew: a.input.crew,
      });
    }
  }

  // pricingSnapshot (décision, ctrl.) : figé au passage de demande/refuse à
  // valide, conservé tant que le vol reste valide ; null pour une demande.
  // Calculé avant le contrôle de crédit : un vol qui reste valide doit être
  // évalué sur ce même snapshot figé, pas sur les tarifs courants (fix task 3,
  // règle du contrôleur), pour rester cohérent avec ce qui le facturera et
  // avec le calcul du crédit disponible des autres vols.
  const pricingSnapshot: Pricing | null = d.status === "valide"
    ? (a.existingSnapshot && a.previousStatus === "valide" ? pricingWithDefaults(a.existingSnapshot) : pricing)
    : null;

  // Décision 1 : crédit contrôlé dès la demande, sauf baptême (spec §10.2).
  // `pricingMode` vaut "standard", "fuel_only" ou "baptism" à ce stade (le mode
  // "custom" ne se décide qu'à la clôture, spec §4.1).
  const payerUid = payerOf(a.input.crew);
  const payer = crew.find((c) => c.uid === payerUid)!;
  if (!a.skipCredit && pricingMode !== "baptism") {
    locks = await checkCredit(tx, db, locks, {
      id: a.id, payerUid, category: payer.category, pricingMode, balance: payer.balance,
      shortName: payer.shortName, plannedMinutes: (a.input.end - a.input.start) / 60_000,
      ownPricing: pricingSnapshot ?? pricing, fallbackPricing: pricing,
    });
  }

  return {
    status: d.status,
    locks,
    fields: {
      start: Timestamp.fromMillis(a.input.start),
      end: Timestamp.fromMillis(a.input.end),
      destination: a.input.destination,
      aircraftId: aircraft.id,
      aircraft: aircraft.registration,
      crew: a.input.crew,
      passengers: a.input.passengers,
      instructorUid: d.instructorUid,
      status: d.status,
      pricingMode,
      baptismTier: a.input.baptism ? a.input.baptismTier : null,
      instruction: a.input.instruction,
      payerUid,
      pricingSnapshot,
      updatedAt: FieldValue.serverTimestamp(),
    },
  };
}
