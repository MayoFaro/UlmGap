// Module pur (sans Firestore) : matrice de droits, instructeur désigné, payeur,
// mode de tarification, conflits. Miroir Dart : lib/core/flight_rules.dart.
// Cas partagés : test/fixtures/flight_rules.json.
import type { Profile } from "../admin/validation";

export type FlightStatus = "demande" | "valide" | "refuse";
export type PricingMode = "standard" | "fuel_only" | "custom" | "baptism";

export interface Person { uid: string; profile: Profile | null }
/** Spec §10.1 : exactement un instructeur et un autre membre avec compte. */
export function isInstructionEligible(crew: Person[]): boolean {
  return crew.length === 2 && crew.filter((p) => p.profile === "instructeur").length === 1;
}

export interface AmphibiousPerson { profile: Profile | null; amphibiousCleared: boolean }
/** Spec §3.6 : équipage d'un appareil amphibie ; null si la règle est respectée. */
export function amphibiousError(crew: AmphibiousPerson[]): string | null {
  const instructors = crew.filter((p) => p.profile === "instructeur");
  if (instructors.length > 0) {
    return instructors.some((p) => p.amphibiousCleared) ? null :
      "Appareil amphibie : l'instructeur doit être lâché amphibie.";
  }
  return crew.some((p) => p.amphibiousCleared) ? null :
    "Appareil amphibie : il faut un pilote lâché amphibie à bord.";
}

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
export interface ExistingFlight extends Slot {
  id: string; status: FlightStatus; deleted: boolean; closed?: boolean;
}

/** Plan 9 : battement fixe entre deux vols (même appareil ou même personne). */
export const FLIGHT_BUFFER_MINUTES = 30;
const BUFFER_MS = FLIGHT_BUFFER_MINUTES * 60_000;

/**
 * Spec §3.5 : vols valide non supprimés, bornes ouvertes (un écart d'exactement
 * 30 min est accepté), même appareil ou même personne. Un vol clôturé n'est jamais en conflit : ses horaires sont
 * ceux de la conduite, pas de la planification (révision du 2026-10-01).
 */
export function findConflict(candidate: Slot, others: ExistingFlight[]): ExistingFlight | null {
  return others.find((o) =>
    o.id !== candidate.id &&
    o.status === "valide" &&
    !o.deleted &&
    o.closed !== true &&
    candidate.start < o.end + BUFFER_MS && o.start < candidate.end + BUFFER_MS &&
    (o.aircraftId === candidate.aircraftId || o.crew.some((u) => candidate.crew.includes(u))),
  ) ?? null;
}

/**
 * Révision du 2026-10-01 : les conflits bloquent la planification, jamais la
 * conduite. Ils ne se contrôlent que pour un vol non clôturé dont le départ
 * est encore à venir.
 */
export function isPlanning(startMs: number, nowMs: number, closed: boolean): boolean {
  return !closed && startMs > nowMs;
}

/** Cause d'un conflit : l'appareil d'abord, sinon les personnes communes. */
export function conflictCause(
  candidate: Slot, other: Slot,
): { kind: "aircraft" | "crew"; members: string[] } {
  if (candidate.aircraftId === other.aircraftId) return { kind: "aircraft", members: [] };
  return { kind: "crew", members: candidate.crew.filter((u) => other.crew.includes(u)) };
}
