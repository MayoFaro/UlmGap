// Lancé par `npm run test:int` (émulateurs Auth + Firestore).
// Vol technique (spec §12) : droits, aucun contrôle de crédit, clôture non
// facturée, régularisation par correction admin, aucune ligne de caisse.
import { afterEach, beforeEach, test } from "node:test";
import * as assert from "node:assert/strict";
import { code, db, draft, FUEL, H, resetCashbox, seedAircraft, seedFlight, seedUser } from "./testkit";
import { createFlight, updateFlight } from "./edit";
import { validateFlight } from "./actions";
import { closeFlight } from "./close";
import { adminUpdateFlight } from "./admin-edit";

beforeEach(resetCashbox);
afterEach(resetCashbox);

const flight = async (id: string) => (await db.collection("flights").doc(id).get()).data()!;
const balance = async (uid: string) => (await db.collection("users").doc(uid).get()).get("balance") as number;
const txs = async (uid: string) =>
  (await db.collection("transactions").where("userUid", "==", uid).get()).docs.map((d) => d.data());
const cashLines = async () => (await db.collection("cashMovements").get()).size;
const TECH = { technical: true, technicalReason: "Convoyage Wonga-Wongué" };

test("instructeur : vol technique créé valide, sans contrôle de crédit (solde 0)", async () => {
  const instr = await seedUser({ profile: "instructeur", balance: 0 });
  const ac = await seedAircraft();
  const r = await createFlight(instr, draft(ac, [instr.uid], TECH));
  assert.equal(r.status, "valide");
  const f = await flight(r.id);
  assert.equal(f.pricingMode, "technical");
  assert.equal(f.technical, true);
  assert.equal(f.technicalReason, "Convoyage Wonga-Wongué");
});

test("lâché : cocher Vol technique est refusé", async () => {
  const lache = await seedUser({ profile: "lache_toute_mission" });
  const ac = await seedAircraft();
  await assert.rejects(createFlight(lache, draft(ac, [lache.uid], TECH)),
    (e) => code(e) === "permission-denied" &&
      (e as Error).message === "Vol technique : réservé aux instructeurs et aux admins.");
});

const MSG = "Impossible de modifier car vol technique sélectionné. Pour modifier, décochez l'option vol technique.";
const payerRefused = (e: unknown) => code(e) === "failed-precondition" && (e as Error).message === MSG;

test("validation en technique de la demande d'un lâché (lâché en tête) : refus, instructeur payeur exigé", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const lache = await seedUser({ profile: "lache_toute_mission" });
  const ac = await seedAircraft();
  const r = await createFlight(lache, draft(ac, [lache.uid, instr.uid]));
  assert.equal(r.status, "demande");
  await assert.rejects(validateFlight(instr, { flightId: r.id, changes: TECH }), payerRefused);
  assert.equal((await flight(r.id)).status, "demande");
});

test("admin : vol technique créé avec un lâché en tête : refus", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const instr = await seedUser({ profile: "instructeur" });
  const lache = await seedUser({ profile: "lache_toute_mission" });
  const ac = await seedAircraft();
  await assert.rejects(createFlight(admin1, draft(ac, [lache.uid, instr.uid], TECH)), payerRefused);
});

test("instructeur en tête et lâché second : vol technique accepté", async () => {
  const instr = await seedUser({ profile: "instructeur", balance: 0 });
  const lache = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const ac = await seedAircraft();
  const r = await createFlight(instr, draft(ac, [instr.uid, lache.uid], TECH));
  assert.equal(r.status, "valide");
  assert.equal((await flight(r.id)).pricingMode, "technical");
});

test("correction admin d'un vol technique plaçant un non-instructeur en tête : refus", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const instr = await seedUser({ profile: "instructeur" });
  const lache = await seedUser({ profile: "lache_toute_mission" });
  const ac = await seedAircraft();
  const start = Date.now() - 3 * H;
  const id = await seedFlight({
    start, end: start + H, crew: [instr.uid, lache.uid], aircraftId: ac,
    pricingMode: "technical", technical: true, technicalReason: "Essai",
  });
  await assert.rejects(adminUpdateFlight(admin1, {
    flightId: id, start, end: start + H, destination: "Lomé", aircraftId: ac, crew: [lache.uid, instr.uid], ...TECH,
  }), payerRefused);
  assert.deepEqual((await flight(id)).crew, [instr.uid, lache.uid]);
});

test("validation en vol technique sans motif : refus", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const lache = await seedUser({ profile: "lache_toute_mission" });
  const ac = await seedAircraft();
  const r = await createFlight(lache, draft(ac, [lache.uid, instr.uid]));
  await assert.rejects(validateFlight(instr, { flightId: r.id, changes: { technical: true } }),
    (e) => code(e) === "invalid-argument" && (e as Error).message === "Motif du vol technique obligatoire.");
  await assert.rejects(
    validateFlight(instr, { flightId: r.id, changes: { ...TECH, instruction: true } }),
    (e) => code(e) === "invalid-argument" &&
      (e as Error).message === "Vol technique : incompatible avec un vol d'instruction.");
});

test("vol technique avec un passager sans compte : accepté", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const ac = await seedAircraft();
  const r = await createFlight(instr, draft(ac, [instr.uid], { ...TECH, passengers: ["Mécano"] }));
  assert.equal((await flight(r.id)).pricingMode, "technical");
});

test("clôture d'un vol technique : 0, association, aucun mouvement de compte ni de caisse", async () => {
  const pilot = await seedUser({ profile: "instructeur", balance: 50_000 });
  const ac = await seedAircraft();
  const id = await seedFlight({
    start: Date.now() - 2 * H, end: Date.now() - H, crew: [pilot.uid], aircraftId: ac,
    pricingMode: "technical", technical: true, technicalReason: "Essai moteur",
  });
  const r = await closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 90, landings: 1 });
  assert.deepEqual(r, { billedAmount: 0, billedTo: "association" });
  assert.equal(await balance(pilot.uid), 50_000);
  assert.equal((await txs(pilot.uid)).length, 0);
  assert.equal(await cashLines(), 0);
  await assert.rejects(
    closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 90, landings: 1 }),
    (e) => code(e) === "failed-precondition"); // déjà clôturé
});

test("clôture d'un vol technique marqué instruction (donnée incohérente) : aucun crédit d'instruction", async () => {
  const instr = await seedUser({ profile: "instructeur", balance: 0 });
  const eleve = await seedUser({ profile: "eleve", balance: 0 });
  const ac = await seedAircraft();
  const id = await seedFlight({
    start: Date.now() - 2 * H, end: Date.now() - H, crew: [instr.uid, eleve.uid], aircraftId: ac,
    pricingMode: "technical", technical: true, technicalReason: "Essai", instruction: true,
  });
  await closeFlight(instr, { ...FUEL, flightId: id, actualMinutes: 60, landings: 1 });
  const f = await flight(id);
  assert.equal(f.instructionCreditUid, null);
  assert.equal(await balance(instr.uid), 0);
  assert.equal(await balance(eleve.uid), 0);
});

test("clôture d'un vol technique avec un montant : refus", async () => {
  const pilot = await seedUser({ profile: "instructeur" });
  const ac = await seedAircraft();
  const id = await seedFlight({
    start: Date.now() - 2 * H, end: Date.now() - H, crew: [pilot.uid], aircraftId: ac,
    passengers: ["Mécano"], pricingMode: "technical", technical: true, technicalReason: "Essai",
  });
  await assert.rejects(
    closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 60, landings: 1, customAmount: 9_000 }),
    (e) => code(e) === "invalid-argument" && (e as Error).message === "Aucun montant pour un vol technique.");
});

test("correction admin : vol clôturé standard → technique rembourse le payeur ; l'inverse le débite", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "instructeur", category: "GAP", balance: 100_000 });
  const ac = await seedAircraft();
  const start = Date.now() - 3 * H;
  const id = await seedFlight({ start, end: start + H, crew: [pilot.uid], aircraftId: ac, pricingMode: "standard" });
  await closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 60, landings: 1 });
  assert.equal(await balance(pilot.uid), 88_000); // GAP 60 min = 12 000

  const body = { flightId: id, start, end: start + H, destination: "Lomé", aircraftId: ac, crew: [pilot.uid] };
  await adminUpdateFlight(admin1, { ...body, ...TECH });
  let f = await flight(id);
  assert.equal(f.pricingMode, "technical");
  assert.equal(f.billedTo, "association");
  assert.equal(f.billedAmount, 0);
  assert.equal(await balance(pilot.uid), 100_000);
  assert.ok((await txs(pilot.uid)).some((t) => t.type === "flight_adjustment" && t.amount === 12_000));

  await adminUpdateFlight(admin1, body);
  f = await flight(id);
  assert.equal(f.pricingMode, "standard");
  assert.equal(f.billedTo, "account");
  assert.equal(await balance(pilot.uid), 88_000);
  assert.equal(await cashLines(), 0);
});

test("correction admin en technique avec un mode ou un montant explicite : refus", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "instructeur" });
  const ac = await seedAircraft();
  const start = Date.now() - 3 * H;
  const id = await seedFlight({
    start, end: start + H, crew: [pilot.uid], aircraftId: ac, passengers: ["Mécano"], pricingMode: "standard",
  });
  await closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 60, landings: 1 });
  const body = {
    flightId: id, start, end: start + H, destination: "Lomé", aircraftId: ac, crew: [pilot.uid],
    passengers: ["Mécano"], ...TECH,
  };
  for (const extra of [{ pricingMode: "standard" }, { pricingMode: "custom", customAmount: 5_000 }, { customAmount: 5_000 }]) {
    await assert.rejects(adminUpdateFlight(admin1, { ...body, ...extra }),
      (e) => code(e) === "invalid-argument" && (e as Error).message === "Aucun montant pour un vol technique.");
  }
});

test("correction admin : vol clôturé « montant différent » → technique efface le montant", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "instructeur", balance: 100_000 });
  const ac = await seedAircraft();
  const start = Date.now() - 3 * H;
  const id = await seedFlight({
    start, end: start + H, crew: [pilot.uid], aircraftId: ac, passengers: ["Mécano"], pricingMode: "standard",
  });
  await closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 60, landings: 1, customAmount: 9_000 });
  assert.equal((await flight(id)).pricingMode, "custom");
  await adminUpdateFlight(admin1, {
    flightId: id, start, end: start + H, destination: "Lomé", aircraftId: ac, crew: [pilot.uid],
    passengers: ["Mécano"], ...TECH,
  });
  const f = await flight(id);
  assert.equal(f.pricingMode, "technical");
  assert.equal(f.customAmount, null);
  assert.equal(f.shortFlightAmount, null);
  assert.equal(f.billedTo, "association");
  assert.equal(await balance(pilot.uid), 100_000);
});

test("recette « ww » : vol passé non clôturé corrigé en technique par un admin, puis clôturé", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const pilot = await seedUser({ profile: "instructeur", balance: 0 });
  const ac = await seedAircraft();
  const start = Date.now() - 5 * H;
  const id = await seedFlight({ start, end: start + 2 * H, crew: [pilot.uid], aircraftId: ac, pricingMode: "standard" });
  await adminUpdateFlight(admin1, {
    flightId: id, start, end: start + 2 * H, destination: "Wonga-Wongué", aircraftId: ac, crew: [pilot.uid], ...TECH,
  });
  await closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 120, landings: 2 });
  assert.equal(await balance(pilot.uid), 0);
  assert.equal((await flight(id)).billedTo, "association");
  assert.equal(await cashLines(), 0);
});
