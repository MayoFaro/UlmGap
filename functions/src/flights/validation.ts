// Validation (pure) des entrées des fonctions de vol.
import { ValidationError, obj, text } from "../admin/validation";

/** Durée prévue minimale. Le plan 3 la lira dans settings/pricing. */
export const MIN_PLANNED_MINUTES = 45;
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
  if (out.some((u) => !u) || new Set(out).size !== out.length) {
    throw new ValidationError("Équipage invalide.");
  }
  return out;
}

function passengerList(v: unknown): string[] {
  if (v === undefined) return [];
  if (!Array.isArray(v)) throw new ValidationError("Passagers invalides.");
  return v.map((n) => text(n, "Nom du passager", 60));
}

export function checkDuration(start: number, end: number): void {
  if (end - start < MIN_PLANNED_MINUTES * 60_000) {
    throw new ValidationError(`Durée prévue minimale : ${MIN_PLANNED_MINUTES} min.`);
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
    aircraftId: text(d.aircraftId, "Appareil", 128),
    crew, passengers,
  };
  if (d.pricingMode !== undefined) out.pricingMode = mode(d.pricingMode);
  return out;
}

export function validateFlightId(data: unknown): string {
  const d = obj(data);
  const id = typeof d.flightId === "string" ? d.flightId.trim() : "";
  if (!id) throw new ValidationError("Vol manquant.");
  return id;
}

export function validateReviewChanges(data: unknown): { flightId: string; changes: ReviewChanges } {
  const d = obj(data);
  const flightId = validateFlightId(d);
  const c = d.changes === undefined ? {} : obj(d.changes);
  const changes: ReviewChanges = {};
  if (c.start !== undefined) changes.start = time(c.start, "Départ");
  if (c.end !== undefined) changes.end = time(c.end, "Fin");
  if (c.destination !== undefined) changes.destination = text(c.destination, "Destination", 80);
  if (c.aircraftId !== undefined) changes.aircraftId = text(c.aircraftId, "Appareil", 128);
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
