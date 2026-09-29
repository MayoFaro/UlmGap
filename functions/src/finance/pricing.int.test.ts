// Lancé par `npm run test:int` (émulateurs Auth + Firestore, projet demo-ulmgap).
// Les tarifs par défaut valent 45 min ; on utilise ici 50 min pour rester
// au-dessous des durées de 60 min employées par les autres tests d'intégration
// de vols (edit.int.test.ts, actions.int.test.ts), qui peuvent s'exécuter en
// parallèle et lisent le même document settings/pricing.
import { test } from "node:test";
import * as assert from "node:assert/strict";
import { createFlight } from "../flights/edit";
import { at, code, db, draft, seedAircraft, seedUser } from "../flights/testkit";
import { DEFAULT_PRICING } from "../rules/pricing";
import { readPricing, updatePricing } from "./pricing-store";

const CUSTOM = {
  flatFee: { GAP: 13_000, GR: 31_000, MIL: 51_000, EXT: 71_000 },
  includedMinutes: 80,
  minPlannedMinutes: 50,
  overtimeHourly: { GAP: 13_000, GR: 31_000, MIL: 31_000, EXT: 31_000 },
  fuelHourlyRate: 13_000,
};

test("readPricing : sans document → DEFAULT_PRICING", async () => {
  const read = await db.runTransaction((tx) => readPricing(tx, db));
  assert.deepEqual(read, DEFAULT_PRICING);
});

test("adminUpdatePricing puis readPricing : nouvelles valeurs", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  await updatePricing(admin1, CUSTOM);
  const snap = await db.collection("settings").doc("pricing").get();
  assert.equal(snap.get("updatedBy"), admin1.uid);
  assert.ok(snap.get("updatedAt"));
  assert.deepEqual(await db.runTransaction((tx) => readPricing(tx, db)), CUSTOM);
});

test("adminUpdatePricing : un non-admin est refusé", async () => {
  const eleve = await seedUser({ profile: "eleve" });
  await assert.rejects(updatePricing(eleve, CUSTOM), (e) => code(e) === "permission-denied");
});

test("adminUpdatePricing : entrée invalide → invalid-argument", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  await assert.rejects(
    updatePricing(admin1, { ...CUSTOM, includedMinutes: 0 }),
    (e) => code(e) === "invalid-argument",
  );
});

test("planFlight applique le minimum courant lu dans settings/pricing (régression checkDuration → planFlight)", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  await updatePricing(admin1, CUSTOM); // minPlannedMinutes: 50
  const me = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  const start = at(80);
  await assert.rejects(
    createFlight(me, draft(a, [me.uid], { start, end: start + 49 * 60_000 })),
    (e) => code(e) === "invalid-argument" &&
      (e as Error).message === "Durée prévue minimale : 50 min.",
  );
  const { status } = await createFlight(me, draft(a, [me.uid], { start, end: start + 50 * 60_000 }));
  assert.equal(status, "valide");
});
