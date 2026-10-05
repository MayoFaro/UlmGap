// Module pur (sans Firestore) : coûts, crédit disponible, facturation à la
// clôture et régularisation. Miroir Dart à venir : lib/core/pricing.dart.
// Cas partagés : test/fixtures/pricing_cases.json.

import { isInstructionEligible } from "./flights";
import type { Person } from "./flights";

export type Category = "GAP" | "GR" | "MIL" | "EXT";
const CATEGORIES: readonly Category[] = ["GAP", "GR", "MIL", "EXT"];

export type BaptismTier = "local" | "nyonye" | "awagne";
export const BAPTISM_TIERS: readonly BaptismTier[] = ["local", "nyonye", "awagne"];

export interface Pricing {
  flatFee: Record<Category, number>;
  /** Temps couvert par le forfait : le dépassement se compte à partir de là. */
  includedMinutes: number;
  /** Jusqu'à cette durée (incluse), le forfait seul est facturé. */
  toleranceMinutes: number;
  minPlannedMinutes: number;
  overtimeHourly: Record<Category, number>;
  fuelHourlyRate: number;
  instructionCredit: number;
  /** Forfait du baptême de l'air selon le tier choisi. */
  baptismFees: Record<BaptismTier, number>;
}

export const DEFAULT_PRICING: Pricing = {
  flatFee: { GAP: 12_000, GR: 30_000, MIL: 50_000, EXT: 70_000 },
  includedMinutes: 60,
  toleranceMinutes: 75,
  minPlannedMinutes: 45,
  overtimeHourly: { GAP: 12_000, GR: 30_000, MIL: 30_000, EXT: 30_000 },
  fuelHourlyRate: 12_000,
  instructionCredit: 20_000,
  baptismFees: { local: 70_000, nyonye: 90_000, awagne: 110_000 },
};

/** Spec §10.1 : durée réelle minimale pour que l'instructeur soit crédité. */
export const INSTRUCTION_MIN_MINUTES = 45;

/** Fusion champ par champ sur DEFAULT_PRICING (cartes par catégorie comprises). */
export function pricingWithDefaults(p: Partial<Pricing> | null | undefined): Pricing {
  return {
    flatFee: { ...DEFAULT_PRICING.flatFee, ...p?.flatFee },
    includedMinutes: p?.includedMinutes ?? DEFAULT_PRICING.includedMinutes,
    toleranceMinutes: p?.toleranceMinutes ?? DEFAULT_PRICING.toleranceMinutes,
    minPlannedMinutes: p?.minPlannedMinutes ?? DEFAULT_PRICING.minPlannedMinutes,
    overtimeHourly: { ...DEFAULT_PRICING.overtimeHourly, ...p?.overtimeHourly },
    fuelHourlyRate: p?.fuelHourlyRate ?? DEFAULT_PRICING.fuelHourlyRate,
    instructionCredit: p?.instructionCredit ?? DEFAULT_PRICING.instructionCredit,
    baptismFees: { ...DEFAULT_PRICING.baptismFees, ...p?.baptismFees },
  };
}

/** Plafond des montants saisis à la clôture (shortFlightAmount, customAmount). */
export const MAX_MANUAL_AMOUNT = 200_000;

/** Coût calculé ; null si standard et d < minPlannedMinutes (montant à saisir). */
export function computedCost(
  mode: "standard" | "fuel_only", minutes: number, category: Category, p: Pricing,
): number | null {
  if (mode === "fuel_only") {
    return Math.round(p.fuelHourlyRate * minutes / 60);
  }
  if (minutes < p.minPlannedMinutes) return null;
  if (minutes <= p.toleranceMinutes) return p.flatFee[category];
  // max(0) : un snapshot incohérent (tolérance < temps couvert) ne donne jamais de dépassement négatif.
  const extra = Math.max(0, minutes - p.includedMinutes);
  return Math.round(p.flatFee[category] + p.overtimeHourly[category] * extra / 60);
}

/**
 * Coût estimé d'un vol prévu (durée prévue ≥ minimum). planFlight vérifie
 * déjà `plannedMinutes ≥ minPlannedMinutes`, donc computedCost ne rend
 * jamais null ici.
 */
export function estimatedCost(
  mode: "standard" | "fuel_only", plannedMinutes: number, category: Category, p: Pricing,
): number {
  return computedCost(mode, plannedMinutes, category, p) as number;
}

/** Spec §4.4 : solde moins le coût estimé des autres vols imputés sur le compte. */
export function availableCredit(balance: number, otherEstimatedCosts: number[]): number {
  return balance - otherEstimatedCosts.reduce((sum, c) => sum + c, 0);
}

/** Montant facturé à la clôture. Lève Error("…") si un montant requis manque. */
export function closingBill(a: {
  mode: "standard" | "fuel_only" | "baptism"; actualMinutes: number; category: Category; pricing: Pricing;
  shortFlightAmount?: number | null; customAmount?: number | null; hasPassenger: boolean;
  baptismTier?: BaptismTier | null;
}): { billedAmount: number; billedTo: "account" | "off_app"; pricingMode: "standard" | "fuel_only" | "custom" | "baptism" } {
  if (a.mode === "baptism") {
    return { billedAmount: a.pricing.baptismFees[a.baptismTier ?? "local"], billedTo: "off_app", pricingMode: "baptism" };
  }
  if (a.customAmount != null) {
    if (!a.hasPassenger) {
      throw new Error("Montant différent réservé aux vols avec un passager sans compte.");
    }
    return { billedAmount: a.customAmount, billedTo: "off_app", pricingMode: "custom" };
  }
  const computed = computedCost(a.mode, a.actualMinutes, a.category, a.pricing);
  if (computed === null) {
    if (a.shortFlightAmount == null) {
      throw new Error(
        `Montant à facturer obligatoire pour un vol de moins de ${a.pricing.minPlannedMinutes} min.`,
      );
    }
    return { billedAmount: a.shortFlightAmount, billedTo: "account", pricingMode: a.mode };
  }
  return { billedAmount: computed, billedTo: "account", pricingMode: a.mode };
}

/**
 * Régularisation (spec §4.5) : mouvements par compte entre l'ancien et le
 * nouveau débit. On rembourse l'ancien débit (+amount) et on prélève le
 * nouveau (−amount), on regroupe par uid selon l'ordre de première
 * apparition, et on omet les totaux nuls.
 */
export function adjustments(
  before: { billedTo: "account" | "off_app" | null; payerUid: string | null; amount: number },
  after: { billedTo: "account" | "off_app" | null; payerUid: string | null; amount: number },
): { uid: string; amount: number }[] {
  const totals = new Map<string, number>();
  const order: string[] = [];
  const add = (uid: string | null, amount: number) => {
    if (!uid) return;
    if (!totals.has(uid)) {
      totals.set(uid, 0);
      order.push(uid);
    }
    totals.set(uid, totals.get(uid)! + amount);
  };
  if (before.billedTo === "account") add(before.payerUid, before.amount);
  if (after.billedTo === "account") add(after.payerUid, -after.amount);
  return order
    .map((uid) => ({ uid, amount: totals.get(uid) as number }))
    .filter((r) => r.amount !== 0);
}

/** Spec §10.1 : crédit dû à l'instructeur à la clôture, ou null. */
export function instructionCreditDue(a: {
  instruction: boolean; actualMinutes: number; crew: Person[]; pricing: Pricing;
}): { uid: string; amount: number } | null {
  // Crédit réglé à 0 dans Tarifs : le crédit est désactivé.
  if (a.pricing.instructionCredit <= 0 || !a.instruction || a.actualMinutes < INSTRUCTION_MIN_MINUTES || !isInstructionEligible(a.crew)) {
    return null;
  }
  const instructor = a.crew.find((p) => p.profile === "instructeur")!;
  return { uid: instructor.uid, amount: a.pricing.instructionCredit };
}

/**
 * Régularisation du crédit d'instruction : retire l'ancien crédit
 * (−amount) et ajoute le nouveau (+amount), regroupés par uid selon l'ordre
 * de première apparition, totaux nuls omis.
 */
export function instructionAdjustments(
  before: { uid: string | null; amount: number },
  after: { uid: string | null; amount: number },
): { uid: string; amount: number }[] {
  const totals = new Map<string, number>();
  const order: string[] = [];
  const add = (uid: string | null, amount: number) => {
    if (!uid) return;
    if (!totals.has(uid)) {
      totals.set(uid, 0);
      order.push(uid);
    }
    totals.set(uid, totals.get(uid)! + amount);
  };
  add(before.uid, -before.amount);
  add(after.uid, after.amount);
  return order
    .map((uid) => ({ uid, amount: totals.get(uid) as number }))
    .filter((r) => r.amount !== 0);
}

/** Code d'appartenance ; toute valeur inconnue est traitée comme "EXT". */
export function toCategory(v: unknown): Category {
  return CATEGORIES.includes(v as Category) ? (v as Category) : "EXT";
}

/**
 * Format des montants (décision 6) : groupes de 3 chiffres séparés par une
 * espace insécable, sans décimales, signe « − » pour un montant négatif.
 */
export function formatFcfa(amount: number): string {
  const rounded = Math.round(Math.abs(amount));
  const grouped = rounded.toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  return `${amount < 0 ? "−" : ""}${grouped} FCFA`;
}
