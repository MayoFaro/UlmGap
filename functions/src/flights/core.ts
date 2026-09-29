// Lectures en transaction, contrôles communs (spec §3.4), conflits (§3.5) et
// verrous. Toutes les lectures précèdent les écritures (règle des transactions).
import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import type { Profile } from "../admin/validation";
import { asInvalid } from "../common/errors";
import { readPricing } from "../finance/pricing-store";
import {
  Decision, ExistingFlight, FlightStatus, PricingMode, conflictCause, findConflict, payerOf,
  resolvePricingMode,
} from "../rules/flights";
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
}

export interface PlanArgs {
  id: string;
  input: FlightInput;
  decide: (crew: CrewInfo[]) => Decision;
  mayChoose: boolean;
  previousMode?: PricingMode;
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
    };
  });
}

async function loadAircraft(tx: Tx, db: Db, id: string): Promise<{ id: string; registration: string }> {
  const s = await tx.get(db.collection("aircraft").doc(id));
  if (!s.exists) throw new HttpsError("not-found", "Appareil introuvable.");
  const registration = (s.get("registration") as string | undefined) ?? "";
  if (s.get("active") !== true) {
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
 * Contrôles communs, décision de statut, mode de tarification, payeur et,
 * si le vol devient ou reste valide, conflits et verrous.
 */
export async function planFlight(tx: Tx, db: Db, a: PlanArgs): Promise<Planned> {
  const crew = await loadCrew(tx, db, a.input.crew);
  const aircraft = await loadAircraft(tx, db, a.input.aircraftId);
  const pricing = await readPricing(tx, db);
  asInvalid(() => checkMinDuration(a.input.start, a.input.end, pricing.minPlannedMinutes));
  const off = crew.find((c) => !c.active);
  if (off) throw new HttpsError("failed-precondition", `${off.shortName} n'est plus actif.`);

  const d = a.decide(crew);
  if (!d.ok) throw new HttpsError("permission-denied", d.reason);

  const pricingMode = resolvePricingMode({
    allGap: crew.every((c) => c.category === "GAP"),
    hasPassenger: a.input.passengers.length > 0,
    mayChoose: a.mayChoose,
    requested: a.input.pricingMode,
    previous: a.previousMode,
  });

  let locks: Ref[] = [];
  if (d.status === "valide") {
    locks = await readLocks(tx, db, aircraft.id, a.input.crew);
    await assertNoConflict(tx, db, {
      id: a.id, start: a.input.start, end: a.input.end, aircraftId: aircraft.id, crew: a.input.crew,
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
      payerUid: payerOf(a.input.crew),
      updatedAt: FieldValue.serverTimestamp(),
    },
  };
}
