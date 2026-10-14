// Validation (pure) des opérations de caisse (spec §11.3, §11.4).
import { obj, ValidationError } from "../admin/validation";
import { CashKind, clubDayString, isValidCashDay, signedCashAmount } from "../rules/cash";

const ADDABLE: readonly CashKind[] = ["fuel_purchase", "maintenance", "off_app_income", "cash_gap"];

/** Jour de l'opération : aujourd'hui par défaut, jamais dans le futur. */
export function cashDay(v: unknown, nowMs: number): string {
  if (v === undefined || v === null) return clubDayString(nowMs);
  if (typeof v !== "string" || !isValidCashDay(v, nowMs)) {
    throw new ValidationError("Date invalide (au plus aujourd'hui).");
  }
  return v;
}

function note(v: unknown, missing: string | null): string | null {
  if (v !== undefined && v !== null && typeof v !== "string") throw new ValidationError("Note invalide.");
  const s = typeof v === "string" ? v.trim() : "";
  if (s.length > 200) throw new ValidationError("Note trop longue (200 caractères au maximum).");
  if (missing && !s) throw new ValidationError(missing);
  return s || null;
}

function missingNote(kind: CashKind): string | null {
  if (kind === "cash_gap") return "Motif obligatoire pour un écart de caisse.";
  if (kind === "maintenance" || kind === "off_app_income") return "Objet obligatoire.";
  return null;
}

/** Achat carburant, maintenance, recette hors app, écart de caisse (montant signé en sortie). */
export function validateAddCashMovement(data: unknown, nowMs: number):
  { kind: CashKind; amount: number; date: string; note: string | null } {
  const d = obj(data);
  const kind = d.kind as CashKind;
  if (!ADDABLE.includes(kind)) throw new ValidationError("Type d'opération invalide.");
  if (typeof d.amount !== "number") throw new ValidationError("Montant invalide.");
  return {
    kind,
    amount: signedCashAmount(kind, d.amount, false),
    date: cashDay(d.date, nowMs),
    note: note(d.note, missingNote(kind)),
  };
}

/** Correction : montant juste saisi (signé d'après le type de la ligne, côté Function). */
export function validateCashCorrection(data: unknown):
  { movementId: string; amount: number; note: string | null } {
  const d = obj(data);
  const movementId = typeof d.movementId === "string" ? d.movementId.trim() : "";
  if (!movementId || movementId.includes("/")) throw new ValidationError("Opération manquante.");
  if (typeof d.amount !== "number" || !Number.isInteger(d.amount)) {
    throw new ValidationError("Montant invalide.");
  }
  return { movementId, amount: d.amount, note: note(d.note, null) };
}
