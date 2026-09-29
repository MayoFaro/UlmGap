// Validation (pure) des tarifs (settings/pricing, spec §2.4).
import { ValidationError } from "../admin/validation";
import { Category, Pricing } from "../rules/pricing";

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

/** Toutes les clés sont exigées ; valeurs entières dans les plages de la spec §2.4. */
export function validatePricing(data: unknown): Pricing {
  const d = record(data, "tarifs");
  return {
    flatFee: byCategory(d.flatFee, "flatFee", 1_000_000),
    includedMinutes: intInRange(d.includedMinutes, "includedMinutes", 1, 600),
    minPlannedMinutes: intInRange(d.minPlannedMinutes, "minPlannedMinutes", 1, 600),
    overtimeHourly: byCategory(d.overtimeHourly, "overtimeHourly", 1_000_000),
    fuelHourlyRate: intInRange(d.fuelHourlyRate, "fuelHourlyRate", 0, 1_000_000),
  };
}
