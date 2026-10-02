// Outils partagés par les tests d'intégration des vols (émulateurs).
import * as admin from "firebase-admin";
import type { Caller } from "../auth/guards";

if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT ?? "demo-ulmgap" });
}
export const db = admin.firestore();
const uniq = () => Math.random().toString(36).slice(2, 8);

export const H = 3_600_000;
/** Instant futur : après-demain à minuit (UTC) + h heures. */
export const at = (h: number) => {
  const d = new Date(Date.now() + 2 * 24 * H);
  d.setUTCHours(0, 0, 0, 0);
  return d.getTime() + h * H;
};

export const code = (e: unknown) => (e as { code?: string }).code;
export const details = (e: unknown) =>
  (e as { details?: { conflict?: Record<string, unknown>; credit?: Record<string, unknown> } }).details;

export async function seedUser(fields: {
  profile: string | null; category?: string; isAdmin?: boolean; active?: boolean; shortName?: string;
  balance?: number;
}): Promise<Caller> {
  const uid = `u-${uniq()}`;
  // Firestore refuse les valeurs `undefined` : on les retire avant de fusionner
  // (Task 6 appelle seedUser({ profile, category: undefined }) en attendant "EXT" par défaut).
  const clean = Object.fromEntries(Object.entries(fields).filter(([, v]) => v !== undefined));
  await db.collection("users").doc(uid).set({
    displayName: uid, shortName: fields.shortName ?? uid.slice(2, 5).toUpperCase(),
    // Solde confortable par défaut : les tests de crédit passent balance: 0 explicitement.
    category: "EXT", isAdmin: false, active: true, balance: 1_000_000, ...clean,
  });
  return { uid, token: { email_verified: true } };
}

export async function seedAircraft(active = true, amphibious = false): Promise<string> {
  const ref = db.collection("aircraft").doc();
  await ref.set({ registration: `F-${uniq().toUpperCase().slice(0, 4)}`, label: "ULM", active, amphibious });
  return ref.id;
}

/** Écrit un vol directement (vols passés, états particuliers). */
export async function seedFlight(fields: Record<string, unknown>): Promise<string> {
  const ref = db.collection("flights").doc();
  const crew = (fields.crew as string[] | undefined) ?? [];
  await ref.set({
    destination: "Lomé", aircraft: "F-TEST", passengers: [], instructorUid: null,
    status: "valide", pricingMode: "standard", isClosed: false, deleted: false,
    payerUid: crew[0], pricingSnapshot: null,
    ...fields,
    start: admin.firestore.Timestamp.fromMillis(fields.start as number),
    end: admin.firestore.Timestamp.fromMillis(fields.end as number),
  });
  return ref.id;
}

export const draft = (aircraftId: string, crew: string[], o: Record<string, unknown> = {}) => ({
  start: at(10), end: at(11), destination: "Lomé", aircraftId, crew, passengers: [], ...o,
});

/** Carburant valide pour les clôtures de test (plan 7, champs obligatoires). */
export const FUEL = { fuelStartExpected: null, fuelStart: 40, fuelAdded: 0, fuelEnd: 30 };
