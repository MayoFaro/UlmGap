// Validation (pure) des opérations de cuve (spec §13).
import { obj, ValidationError } from "../admin/validation";
import { cashDay } from "./cash-validation";

function note(v: unknown): string | null {
  if (v !== undefined && v !== null && typeof v !== "string") throw new ValidationError("Note invalide.");
  const s = typeof v === "string" ? v.trim() : "";
  if (s.length > 200) throw new ValidationError("Note trop longue (200 caractères au maximum).");
  return s || null;
}

function intInRange(v: unknown, min: number, max: number, message: string): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < min || v > max) {
    throw new ValidationError(message);
  }
  return v;
}

/** Plein d'un appareil hors vol, pris dans la cuve. */
export function validateAircraftFill(data: unknown, nowMs: number):
  { aircraftId: string; liters: number; date: string; note: string | null } {
  const d = obj(data);
  const aircraftId = typeof d.aircraftId === "string" ? d.aircraftId.trim() : "";
  if (!aircraftId || aircraftId.includes("/")) throw new ValidationError("Appareil manquant.");
  return {
    aircraftId,
    liters: intInRange(d.liters, 1, 100, "Litres invalides (1 à 100)."),
    date: cashDay(d.date, nowMs),
    note: note(d.note),
  };
}

/** Relevé de jauge : niveau mesuré de la cuve (0 accepté). */
export function validateGaugeReading(data: unknown, nowMs: number):
  { measuredLiters: number; date: string; note: string | null } {
  const d = obj(data);
  return {
    measuredLiters: intInRange(d.measuredLiters, 0, 100_000, "Niveau mesuré invalide (0 à 100 000 L)."),
    date: cashDay(d.date, nowMs),
    note: note(d.note),
  };
}
