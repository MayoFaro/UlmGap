// Lancé par `npm run test:int` (émulateurs Auth + Firestore).
// Contrôle du crédit dès la demande (décision 1), tarifs figés à la
// validation (pricingSnapshot) et minPlannedMinutes lu dans les tarifs.
// Les tests qui modifient settings/pricing la restaurent dans un `finally`
// (fichiers d'intégration exécutés l'un après l'autre, cf. run-tests.js).
import { test } from "node:test";
import * as assert from "node:assert/strict";
import {
  at, code, db, details, draft, seedAircraft, seedFlight, seedUser,
} from "./testkit";
import { createFlight, updateFlight } from "./edit";
import { validateFlight } from "./actions";
import { updatePricing } from "../finance/pricing-store";
import { DEFAULT_PRICING } from "../rules/pricing";

const get = async (id: string) => (await db.collection("flights").doc(id).get()).data()!;
const credit = (e: unknown) => details(e)?.credit as
  { missing?: number; available?: number; cost?: number } | undefined;

test("crédit insuffisant à la demande : refusée, montant manquant et message", async () => {
  const eleve = await seedUser({ profile: "eleve", balance: 0, shortName: "ELV" });
  const instr = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  await assert.rejects(
    createFlight(eleve, draft(a, [eleve.uid, instr.uid])), // 60 min, EXT par défaut → 70 000
    (e) => {
      assert.equal(code(e), "failed-precondition");
      assert.equal((e as Error).message, "Crédit insuffisant pour ELV : il manque 70 000 FCFA.");
      assert.deepEqual(credit(e), { missing: 70_000, available: 0, cost: 70_000 });
      return true;
    },
  );
});

test("crédit tout juste suffisant : demande acceptée", async () => {
  const eleve = await seedUser({ profile: "eleve", balance: 70_000 });
  const instr = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  const { status } = await createFlight(eleve, draft(a, [eleve.uid, instr.uid]));
  assert.equal(status, "demande");
});

test("crédit déjà réservé par un autre vol validé du même compte : second vol refusé", async () => {
  const eleve = await seedUser({ profile: "eleve", balance: 70_000 });
  const adm = await seedUser({ profile: null, isAdmin: true });
  const a1 = await seedAircraft();
  // L'admin crée directement un vol valide pour l'élève (70 000 réservés).
  const { status: s1 } = await createFlight(adm, draft(a1, [eleve.uid]));
  assert.equal(s1, "valide");
  const a2 = await seedAircraft();
  await assert.rejects(
    createFlight(adm, draft(a2, [eleve.uid], { start: at(20), end: at(21) })),
    (e) => code(e) === "failed-precondition" && credit(e)?.missing === 70_000,
  );
});

test("fuel_only : coût carburant utilisé pour le contrôle de crédit (60 min → 12 000)", async () => {
  const gap = await seedUser({ profile: "lache_toute_mission", category: "GAP", balance: 0 });
  const a = await seedAircraft();
  await assert.rejects(
    createFlight(gap, draft(a, [gap.uid], { passengers: ["Paul"] })), // GAP + passager → fuel_only
    (e) => code(e) === "failed-precondition" && credit(e)?.cost === 12_000 && credit(e)?.missing === 12_000,
  );
});

test("admin : soumis aux mêmes règles de crédit que les autres créateurs", async () => {
  const adm = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "instructeur", balance: 0 });
  const a = await seedAircraft();
  await assert.rejects(
    createFlight(adm, draft(a, [pilot.uid])),
    (e) => code(e) === "failed-precondition" && credit(e)?.missing === 70_000,
  );
});

test("validation refusée si le crédit est devenu insuffisant entre-temps", async () => {
  const eleve = await seedUser({ profile: "eleve", balance: 70_000 });
  const instr = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  const { id } = await createFlight(eleve, draft(a, [eleve.uid, instr.uid])); // demande, ne réserve rien
  const adm = await seedUser({ profile: null, isAdmin: true });
  // Le crédit de l'élève est réservé ailleurs entre-temps par un vol valide.
  await createFlight(adm, draft(await seedAircraft(), [eleve.uid], { start: at(20), end: at(21) }));
  await assert.rejects(
    validateFlight(instr, { flightId: id }),
    (e) => code(e) === "failed-precondition" && credit(e)?.missing === 70_000,
  );
  assert.equal((await get(id)).status, "demande");
});

test("tarifs figés : le pricingSnapshot ne change pas après modification des tarifs", async () => {
  const instr = await seedUser({ profile: "instructeur" }); // EXT par défaut, solde confortable
  const a = await seedAircraft();
  const { id } = await createFlight(instr, draft(a, [instr.uid])); // instructeur seul → valide
  const before = await get(id);
  assert.equal(before.status, "valide");
  assert.equal(before.pricingSnapshot.flatFee.EXT, 70_000);

  const admin1 = await seedUser({ profile: null, isAdmin: true });
  try {
    await updatePricing(admin1, {
      ...DEFAULT_PRICING, flatFee: { ...DEFAULT_PRICING.flatFee, EXT: 99_999 },
    });
    await updateFlight(instr, { flightId: id, ...draft(a, [instr.uid], { destination: "Kara" }) });
    const after = await get(id);
    assert.equal(after.destination, "Kara");
    assert.equal(after.pricingSnapshot.flatFee.EXT, 70_000);
  } finally {
    await updatePricing(admin1, DEFAULT_PRICING);
  }
});

test("crédit d'un vol qui reste valide : calculé sur le snapshot figé, pas les tarifs courants", async () => {
  const instr = await seedUser({ profile: "instructeur", balance: 70_000 }); // solde tout juste suffisant
  const a = await seedAircraft();
  const { id } = await createFlight(instr, draft(a, [instr.uid])); // valide, snapshot EXT 70 000
  assert.equal((await get(id)).pricingSnapshot.flatFee.EXT, 70_000);

  const admin1 = await seedUser({ profile: null, isAdmin: true });
  try {
    // Au tarif courant (80 000), le solde de 70 000 ne suffirait plus : le
    // contrôle de crédit d'un vol qui reste valide doit utiliser le snapshot
    // figé (70 000), pas le tarif courant, pour rester cohérent avec la
    // facturation et avec le calcul du crédit disponible des autres vols.
    await updatePricing(admin1, {
      ...DEFAULT_PRICING, flatFee: { ...DEFAULT_PRICING.flatFee, EXT: 80_000 },
    });
    const { status } = await updateFlight(instr,
      { flightId: id, ...draft(a, [instr.uid], { destination: "Kara" }) });
    assert.equal(status, "valide");
    const after = await get(id);
    assert.equal(after.destination, "Kara");
    assert.equal(after.pricingSnapshot.flatFee.EXT, 70_000);
  } finally {
    await updatePricing(admin1, DEFAULT_PRICING);
  }
});

test("minPlannedMinutes lu dans les tarifs : 30 min → un vol de 35 min accepté", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const me = await seedUser({ profile: "instructeur" });
  const a = await seedAircraft();
  try {
    await updatePricing(admin1, { ...DEFAULT_PRICING, minPlannedMinutes: 30 });
    const start = at(90);
    const { status } = await createFlight(me, draft(a, [me.uid], { start, end: start + 35 * 60_000 }));
    assert.equal(status, "valide");
  } finally {
    await updatePricing(admin1, DEFAULT_PRICING);
  }
});

test("concurrence : deux créations simultanées du même compte débité, le crédit n'en couvre qu'une", async () => {
  const instr = await seedUser({ profile: "instructeur", balance: 70_000 });
  const a1 = await seedAircraft();
  const a2 = await seedAircraft();
  const r = await Promise.allSettled([
    createFlight(instr, draft(a1, [instr.uid])), // valide directement (créateur instructeur)
    createFlight(instr, draft(a2, [instr.uid], { start: at(95), end: at(96) })), // créneau distinct
  ]);
  assert.equal(r.filter((x) => x.status === "fulfilled").length, 1);
  const rejected = r.find((x) => x.status === "rejected") as PromiseRejectedResult;
  assert.equal(code(rejected.reason), "failed-precondition");
});

// Régression : un vol sans compte (crew vide impossible en pratique, mais un
// vol seedé sans payerUid) ne doit jamais planter la requête `where`.
test("seedFlight : payerUid par défaut = premier de l'équipage", async () => {
  const p = await seedUser({ profile: "instructeur" });
  const id = await seedFlight({
    start: at(200), end: at(201), aircraftId: await seedAircraft(), crew: [p.uid], createdBy: p.uid,
  });
  assert.equal((await get(id)).payerUid, p.uid);
});
