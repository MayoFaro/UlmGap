// Module pur (sans Firestore) : matrice de droits, instructeur désigné, payeur,
// mode de tarification, conflits. Miroir Dart : lib/core/flight_rules.dart.
// Cas partagés : test/fixtures/flight_rules.json.
import type { Profile } from "../admin/validation";

export type FlightStatus = "demande" | "valide" | "refuse";
export type PricingMode = "standard" | "fuel_only" | "custom";

export interface Person { uid: string; profile: Profile | null }
export interface Creator extends Person { isAdmin: boolean }

export type Decision =
  | { ok: true; status: "demande" | "valide"; instructorUid: string | null }
  | { ok: false; reason: string };

/** Premier instructeur de l'équipage autre que le créateur, sinon null. */
export function designatedInstructor(creatorUid: string, crew: Person[]): string | null {
  return crew.find((p) => p.uid !== creatorUid && p.profile === "instructeur")?.uid ?? null;
}

/** Spec §3.2. L'admin échappe à la matrice (pas aux contrôles communs). */
export function decideStatus(creator: Creator, crew: Person[], passengers: number): Decision {
  const instructorUid = designatedInstructor(creator.uid, crew);
  if (creator.isAdmin || creator.profile === "instructeur") {
    return { ok: true, status: "valide", instructorUid };
  }
  if (!crew.some((p) => p.uid === creator.uid)) {
    return { ok: false, reason: "Vous devez faire partie de l'équipage." };
  }
  if (creator.profile === null) {
    return { ok: false, reason: "Un compte non pilote ne peut pas créer de vol." };
  }
  if (instructorUid) return { ok: true, status: "demande", instructorUid };
  if (creator.profile === "eleve") {
    return {
      ok: false,
      reason: "Impossible de créer un vol à votre profit sans la présence d'un instructeur.",
    };
  }
  if (crew.length + passengers === 2 && creator.profile === "lache_solo") {
    return { ok: false, reason: "Un lâché solo ne vole à deux qu'avec un instructeur." };
  }
  return { ok: true, status: "valide", instructorUid: null };
}

/** Spec §4.2 : le premier inscrit dans crew paie. */
export function payerOf(crew: string[]): string {
  return crew[0];
}

/** Spec §4.1 (custom se décide à la clôture, plan 3). */
export function resolvePricingMode(a: {
  allGap: boolean; hasPassenger: boolean; mayChoose: boolean;
  requested?: PricingMode; previous?: PricingMode;
}): "standard" | "fuel_only" {
  if (!a.allGap) return "standard";
  if (a.hasPassenger) return "fuel_only";
  if (!a.mayChoose) return a.previous === "fuel_only" ? "fuel_only" : "standard";
  return (a.requested ?? a.previous ?? "standard") === "fuel_only" ? "fuel_only" : "standard";
}

/** Décision utilisateur : hors instructeurs et admins, le créateur est le compte débité. */
export function checkPayer(creator: Creator, crew: string[]): string | null {
  if (creator.isAdmin || creator.profile === "instructeur") return null;
  if (!crew.includes(creator.uid)) return null; // laissé à la matrice (decideStatus)
  return crew[0] === creator.uid
    ? null
    : "Le compte débité doit être le vôtre : placez-vous en premier.";
}

export interface Slot { id?: string; start: number; end: number; aircraftId: string; crew: string[] }
export interface ExistingFlight extends Slot { id: string; status: FlightStatus; deleted: boolean }

/** Spec §3.5 : vols valide non supprimés, bornes ouvertes, même appareil ou même personne. */
export function findConflict(candidate: Slot, others: ExistingFlight[]): ExistingFlight | null {
  return others.find((o) =>
    o.id !== candidate.id &&
    o.status === "valide" &&
    !o.deleted &&
    candidate.start < o.end && o.start < candidate.end &&
    (o.aircraftId === candidate.aircraftId || o.crew.some((u) => candidate.crew.includes(u))),
  ) ?? null;
}

/** Cause d'un conflit : l'appareil d'abord, sinon les personnes communes. */
export function conflictCause(
  candidate: Slot, other: Slot,
): { kind: "aircraft" | "crew"; members: string[] } {
  if (candidate.aircraftId === other.aircraftId) return { kind: "aircraft", members: [] };
  return { kind: "crew", members: candidate.crew.filter((u) => other.crew.includes(u)) };
}
