// Caisse (spec §11) : types d'opération, signes, jour du club. Module pur,
// sans Firestore.
import { ValidationError } from "../admin/validation";
import { clubDay } from "./club-day";

export type CashKind =
  "fuel_credit" | "fuel_purchase" | "maintenance" | "off_app_income" | "cash_gap" | "opening";

export const CASH_KINDS: readonly CashKind[] = [
  "fuel_credit", "fuel_purchase", "maintenance", "off_app_income", "cash_gap", "opening",
];

/** +1 : entrée, −1 : sortie, 0 : les deux (écart de caisse). */
export function cashSign(kind: CashKind): 1 | -1 | 0 {
  if (kind === "fuel_purchase" || kind === "maintenance") return -1;
  if (kind === "cash_gap") return 0;
  return 1;
}

/**
 * Montant signé d'une saisie : positive pour une entrée ou une sortie,
 * signée pour un écart. Zéro n'est accepté que pour une correction
 * (montant juste nul = opération annulée).
 */
export function signedCashAmount(kind: CashKind, input: number, allowZero: boolean): number {
  if (!Number.isInteger(input)) throw new ValidationError("Montant invalide.");
  if (input === 0) {
    if (!allowZero) throw new ValidationError("Montant invalide (non nul).");
    return 0;
  }
  const sign = cashSign(kind);
  if (sign === 0) return input;
  if (input < 0) throw new ValidationError("Montant invalide (positif).");
  return sign * input;
}

/** « AAAA-MM-JJ » du jour du club. */
export function clubDayString(ms: number): string {
  return new Date(clubDay(ms) * 86_400_000).toISOString().slice(0, 10);
}

/** Jour réel « AAAA-MM-JJ », depuis 2000, au plus aujourd'hui (jour du club). */
export function isValidCashDay(day: string, nowMs: number): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || day < "2000-01-01") return false;
  const ms = Date.parse(`${day}T00:00:00Z`);
  if (Number.isNaN(ms) || new Date(ms).toISOString().slice(0, 10) !== day) return false;
  return day <= clubDayString(nowMs);
}

/** « 12/10/2026 » */
export function formatCashDay(day: string): string {
  const [y, m, d] = day.split("-");
  return `${d}/${m}/${y}`;
}
