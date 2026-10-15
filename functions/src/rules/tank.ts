// Module pur : cuve du club et carburant fourni par un pilote (spec §13).
import { creditAdjustments } from "./pricing";

export type TankKind = "refill" | "flight" | "aircraft_fill" | "gauge" | "flight_adjustment";

/** Crédit dû au pilote qui a fourni [liters] litres de son bidon perso. */
export function supplyCredit(liters: number, price: number): number {
  return Math.round(liters * price);
}

/** Régularisation du crédit « carburant fourni » (même algorithme que l'instruction). */
export const supplyAdjustments: typeof creditAdjustments = creditAdjustments;
