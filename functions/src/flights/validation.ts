// Validation (pure) des entrées des fonctions de vol.
import { ValidationError, obj, text } from "../admin/validation";
import { MAX_MANUAL_AMOUNT, formatFcfa } from "../rules/pricing";

/** Durée prévue maximale. */
export const MAX_PLANNED_HOURS = 12;
/** Horizon maximal de planification, en jours avant le départ. */
export const MAX_ADVANCE_DAYS = 366;
export const MAX_ABOARD = 2;

type ChosenMode = "standard" | "fuel_only";

export interface FlightInput {
  start: number; // ms depuis l'époque
  end: number;
  destination: string;
  aircraftId: string;
  crew: string[];
  passengers: string[];
  pricingMode?: ChosenMode;
}

export interface ReviewChanges {
  start?: number;
  end?: number;
  destination?: string;
  aircraftId?: string;
  pricingMode?: ChosenMode;
}

function time(v: unknown, field: string): number {
  if (typeof v !== "number" || !Number.isSafeInteger(v) || v <= 0) {
    throw new ValidationError(`${field} invalide.`);
  }
  return v;
}

function mode(v: unknown): ChosenMode {
  if (v !== "standard" && v !== "fuel_only") throw new ValidationError("Mode de tarification invalide.");
  return v;
}

function crewList(v: unknown): string[] {
  if (!Array.isArray(v) || v.length === 0) {
    throw new ValidationError("Au moins un membre d'équipage avec compte.");
  }
  const out = v.map((u) => (typeof u === "string" ? u.trim() : ""));
  if (out.some((u) => !u || u.includes("/")) || new Set(out).size !== out.length) {
    throw new ValidationError("Équipage invalide.");
  }
  return out;
}

/** Un identifiant contenant « / » casserait un chemin Firestore : rejeté proprement. */
function checkNoSlash(v: string, field: string): string {
  if (v.includes("/")) throw new ValidationError(`${field} invalide.`);
  return v;
}

function passengerList(v: unknown): string[] {
  if (v === undefined) return [];
  if (!Array.isArray(v)) throw new ValidationError("Passagers invalides.");
  return v.map((n) => text(n, "Nom du passager", 60));
}

export function checkDuration(start: number, end: number): void {
  if (end <= start) {
    throw new ValidationError("L'heure de fin doit suivre le départ.");
  }
  if (end - start > MAX_PLANNED_HOURS * 3_600_000) {
    throw new ValidationError(`Durée prévue maximale : ${MAX_PLANNED_HOURS} h.`);
  }
}

/**
 * Durée prévue minimale (settings/pricing, spec §2.4) : vérifiée par
 * planFlight, pas par la validation pure (le minimum peut changer sans
 * redéployer les fonctions).
 */
export function checkMinDuration(start: number, end: number, minPlannedMinutes: number): void {
  if (end - start < minPlannedMinutes * 60_000) {
    throw new ValidationError(`Durée prévue minimale : ${minPlannedMinutes} min.`);
  }
}

/** Rejette un départ trop lointain (saisie erronée, ex. mauvaise année). */
export function checkHorizon(start: number, now: number): void {
  if (start - now > MAX_ADVANCE_DAYS * 24 * 3_600_000) {
    throw new ValidationError(`Départ trop lointain (${MAX_ADVANCE_DAYS} jours au maximum).`);
  }
}

export function validateFlightInput(data: unknown): FlightInput {
  const d = obj(data);
  const start = time(d.start, "Départ");
  const end = time(d.end, "Fin");
  checkDuration(start, end);
  const crew = crewList(d.crew);
  const passengers = passengerList(d.passengers);
  if (crew.length + passengers.length > MAX_ABOARD) {
    throw new ValidationError(`${MAX_ABOARD} personnes à bord au maximum.`);
  }
  const out: FlightInput = {
    start, end,
    destination: text(d.destination, "Destination", 80),
    aircraftId: checkNoSlash(text(d.aircraftId, "Appareil", 128), "Appareil"),
    crew, passengers,
  };
  if (d.pricingMode !== undefined) out.pricingMode = mode(d.pricingMode);
  return out;
}

export function validateFlightId(data: unknown): string {
  const d = obj(data);
  const id = typeof d.flightId === "string" ? d.flightId.trim() : "";
  if (!id) throw new ValidationError("Vol manquant.");
  return checkNoSlash(id, "Identifiant de vol");
}

export function validateReviewChanges(data: unknown): { flightId: string; changes: ReviewChanges } {
  const d = obj(data);
  const flightId = validateFlightId(d);
  const c = d.changes === undefined ? {} : obj(d.changes);
  const changes: ReviewChanges = {};
  if (c.start !== undefined) changes.start = time(c.start, "Départ");
  if (c.end !== undefined) changes.end = time(c.end, "Fin");
  if (c.destination !== undefined) changes.destination = text(c.destination, "Destination", 80);
  if (c.aircraftId !== undefined) {
    changes.aircraftId = checkNoSlash(text(c.aircraftId, "Appareil", 128), "Appareil");
  }
  if (c.pricingMode !== undefined) changes.pricingMode = mode(c.pricingMode);
  return { flightId, changes };
}

export function validateRefusal(data: unknown): { flightId: string; reason: string | null } {
  const d = obj(data);
  const flightId = validateFlightId(d);
  const raw = typeof d.reason === "string" ? d.reason.trim() : "";
  if (raw.length > 200) throw new ValidationError("Motif trop long (200 caractères au maximum).");
  return { flightId, reason: raw || null };
}

function actualMinutes(v: unknown): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < 1 || v > 720) {
    throw new ValidationError("Durée réelle invalide (1 à 720 min).");
  }
  return v;
}

/** Nombre d'atterrissages ou d'amerrissages saisi à la clôture (plan 4b). */
function count(v: unknown, label: string): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v > 99) {
    throw new ValidationError(`Nombre ${label} invalide (0 à 99).`);
  }
  return v;
}

/** Plan 4b, décision 3 : au moins un posé au total. */
export function checkLandingsTotal(landings: number, waterLandings: number): void {
  if (landings + waterLandings < 1) throw new ValidationError("Au moins un atterrissage ou amerrissage.");
}

/** Carburant (spec §9) : litres entiers de 0 à 100. */
export const MAX_FUEL_LITERS = 100;

function liters(v: unknown, label: string): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v > MAX_FUEL_LITERS) {
    throw new ValidationError(`${label} invalide (0 à ${MAX_FUEL_LITERS} L).`);
  }
  return v;
}

/** Plafond des montants saisis à la clôture (décision 5, spec §2.4). */
function manualAmount(v: unknown, field: string): number | null {
  if (v === undefined || v === null) return null;
  if (typeof v !== "number" || !Number.isInteger(v) || v < 0) {
    throw new ValidationError(`${field} invalide.`);
  }
  if (v > MAX_MANUAL_AMOUNT) {
    throw new ValidationError(`Montant trop élevé (${formatFcfa(MAX_MANUAL_AMOUNT)} au maximum).`);
  }
  return v;
}

export function validateClosing(data: unknown): {
  flightId: string;
  actualMinutes: number;
  shortFlightAmount: number | null;
  customAmount: number | null;
  landings: number;
  waterLandings: number;
  fuelStartExpected: number | null;
  fuelStart: number;
  fuelAdded: number;
  fuelEnd: number;
} {
  const d = obj(data);
  const flightId = validateFlightId(d);
  const landings = count(d.landings, "d'atterrissages");
  const waterLandings = d.waterLandings === undefined ? 0 : count(d.waterLandings, "d'amerrissages");
  checkLandingsTotal(landings, waterLandings);
  return {
    flightId,
    actualMinutes: actualMinutes(d.actualMinutes),
    shortFlightAmount: manualAmount(d.shortFlightAmount, "Montant à facturer"),
    customAmount: manualAmount(d.customAmount, "Montant différent"),
    landings,
    waterLandings,
    fuelStartExpected: d.fuelStartExpected == null ? null : liters(d.fuelStartExpected, "Carburant prévu"),
    fuelStart: liters(d.fuelStart, "Carburant au départ"),
    fuelAdded: liters(d.fuelAdded, "Carburant ajouté"),
    fuelEnd: liters(d.fuelEnd, "Carburant rangé"),
  };
}

export interface AdminUpdate {
  flightId: string;
  input: FlightInput;
  pricingMode?: "standard" | "fuel_only" | "custom";
  actualMinutes?: number;
  shortFlightAmount?: number | null;
  customAmount?: number | null;
  landings?: number;
  waterLandings?: number;
  fuelStart?: number;
  fuelAdded?: number;
  fuelEnd?: number;
}

/**
 * Correction admin (adminUpdateFlight) : les champs du vol comme
 * validateFlightInput, et les champs de clôture comme validateClosing.
 * Champs de clôture absents = inchangés ; `null` efface un montant. Le mode
 * est rendu à part (« custom » n'existe qu'à la clôture), jamais dans `input`.
 */
export function validateAdminUpdate(data: unknown): AdminUpdate {
  const d = obj(data);
  const flightId = validateFlightId(d);
  const input = validateFlightInput({ ...d, pricingMode: undefined });
  const out: AdminUpdate = { flightId, input };
  if (d.pricingMode !== undefined) {
    out.pricingMode = d.pricingMode === "custom" ? "custom" : mode(d.pricingMode);
  }
  if (d.actualMinutes !== undefined) out.actualMinutes = actualMinutes(d.actualMinutes);
  if (d.landings !== undefined) out.landings = count(d.landings, "d'atterrissages");
  if (d.waterLandings !== undefined) out.waterLandings = count(d.waterLandings, "d'amerrissages");
  if (d.fuelStart !== undefined) out.fuelStart = liters(d.fuelStart, "Carburant au départ");
  if (d.fuelAdded !== undefined) out.fuelAdded = liters(d.fuelAdded, "Carburant ajouté");
  if (d.fuelEnd !== undefined) out.fuelEnd = liters(d.fuelEnd, "Carburant rangé");
  if (d.shortFlightAmount !== undefined) {
    out.shortFlightAmount = manualAmount(d.shortFlightAmount, "Montant à facturer");
  }
  if (d.customAmount !== undefined) out.customAmount = manualAmount(d.customAmount, "Montant différent");
  if (out.pricingMode === "custom" && d.customAmount !== undefined && out.customAmount == null) {
    throw new ValidationError("Montant différent obligatoire en mode « montant différent ».");
  }
  if ((out.pricingMode === "standard" || out.pricingMode === "fuel_only") && out.customAmount != null) {
    throw new ValidationError("Montant différent incompatible avec ce mode.");
  }
  return out;
}
