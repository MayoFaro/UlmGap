// Validation (pure) des tarifs (settings/pricing, spec §2.4) et des crédits /
// corrections de compte (task 5).
import { obj, ValidationError } from "../admin/validation";
import { BAPTISM_TIERS, BaptismTier, Category, Pricing } from "../rules/pricing";

const CATEGORIES: readonly Category[] = ["GAP", "GR", "MIL", "EXT"];

function record(v: unknown, field: string): Record<string, unknown> {
  if (!v || typeof v !== "object") throw new ValidationError(`Tarifs invalides : ${field}.`);
  return v as Record<string, unknown>;
}

function intInRange(v: unknown, field: string, min: number, max: number): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < min || v > max) {
    throw new ValidationError(`Tarifs invalides : ${field}.`);
  }
  return v;
}

function byCategory(v: unknown, field: string, max: number): Record<Category, number> {
  const d = record(v, field);
  const out = {} as Record<Category, number>;
  for (const c of CATEGORIES) out[c] = intInRange(d[c], `${field}.${c}`, 0, max);
  return out;
}

function baptismFees(v: unknown): Record<BaptismTier, number> {
  const d = record(v, "baptismFees");
  const out = {} as Record<BaptismTier, number>;
  for (const t of BAPTISM_TIERS) out[t] = intInRange(d[t], `baptismFees.${t}`, 0, 1_000_000);
  return out;
}

/** Toutes les clés sont exigées ; valeurs entières dans les plages de la spec §2.4. */
export function validatePricing(data: unknown): Pricing {
  const d = record(data, "tarifs");
  const includedMinutes = intInRange(d.includedMinutes, "includedMinutes", 1, 600);
  const toleranceMinutes = intInRange(d.toleranceMinutes, "toleranceMinutes", 1, 600);
  if (toleranceMinutes < includedMinutes) {
    throw new ValidationError("La tolérance doit être au moins égale au temps couvert.");
  }
  return {
    flatFee: byCategory(d.flatFee, "flatFee", 1_000_000),
    includedMinutes,
    toleranceMinutes,
    minPlannedMinutes: intInRange(d.minPlannedMinutes, "minPlannedMinutes", 1, 600),
    overtimeHourly: byCategory(d.overtimeHourly, "overtimeHourly", 1_000_000),
    fuelHourlyRate: intInRange(d.fuelHourlyRate, "fuelHourlyRate", 0, 1_000_000),
    instructionCredit: intInRange(d.instructionCredit, "instructionCredit", 0, 1_000_000),
    baptismFees: baptismFees(d.baptismFees),
  };
}

function accountUid(v: unknown): string {
  const s = typeof v === "string" ? v.trim() : "";
  if (!s || s.includes("/")) throw new ValidationError("Compte manquant.");
  return s;
}

function amountInt(v: unknown): number {
  if (typeof v !== "number" || !Number.isInteger(v)) throw new ValidationError("Montant invalide.");
  return v;
}

function optionalReason(v: unknown): string | null {
  if (v === undefined || v === null) return null;
  const s = typeof v === "string" ? v.trim() : "";
  if (s.length > 200) throw new ValidationError("Motif trop long (200 caractères au maximum).");
  return s || null;
}

/**
 * Crédit (versement) d'un compte par un instructeur ou un admin. Aucun
 * plafond (décision utilisateur) : un montant entier positif est toujours
 * accepté, y compris 1 000 000.
 */
export function validateCredit(data: unknown): { userUid: string; amount: number; reason: string | null } {
  const d = obj(data);
  const userUid = accountUid(d.userUid);
  const amount = amountInt(d.amount);
  if (amount <= 0) throw new ValidationError("Montant invalide.");
  return { userUid, amount, reason: optionalReason(d.reason) };
}

/**
 * Correction d'un compte par un instructeur ou un admin (révision du
 * 2026-10-01) : on saisit le **nouveau solde** (entier, nul ou négatif
 * compris) ; l'écart est calculé dans la transaction. Motif obligatoire.
 */
export function validateCorrection(data: unknown): { userUid: string; newBalance: number; reason: string } {
  const d = obj(data);
  const userUid = accountUid(d.userUid);
  const newBalance = d.newBalance;
  if (typeof newBalance !== "number" || !Number.isInteger(newBalance)) {
    throw new ValidationError("Nouveau solde invalide.");
  }
  const reason = typeof d.reason === "string" ? d.reason.trim() : "";
  if (!reason) throw new ValidationError("Motif obligatoire pour une correction.");
  if (reason.length > 200) throw new ValidationError("Motif trop long (200 caractères au maximum).");
  return { userUid, newBalance, reason };
}
