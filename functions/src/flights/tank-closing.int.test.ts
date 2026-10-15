// Lancé par `npm run test:int` (émulateurs Auth + Firestore).
// Provenance du carburant à la clôture (spec §13.2, §13.4) : mouvement de
// cuve, crédit « carburant fourni » (bidon perso), régularisations admin.
import { afterEach, beforeEach, test } from "node:test";
import * as assert from "node:assert/strict";
import * as admin from "firebase-admin";
import { code, db, FUEL, H, resetCashbox, resetTank, seedAircraft, seedFlight, seedUser } from "./testkit";
import { closeFlight } from "./close";
import { adminDeleteFlight, adminUpdateFlight } from "./admin-edit";
import { addAircraftFill } from "../finance/tank";
import { clubDayString } from "../rules/cash";

beforeEach(async () => {
  await resetTank();
  await resetCashbox();
  // Prix du litre fixé à 600 pour des montants ronds (le défaut est 595) ; les autres tarifs gardent leur défaut.
  await db.doc("settings/pricing").set({ fuelLiterPrice: 600 });
});
afterEach(async () => { await resetTank(); await resetCashbox(); });

const SUPPLIER_OUT = "Le pilote qui a fourni le carburant doit faire partie de l'équipage.";

const getFlight = async (id: string) => (await db.collection("flights").doc(id).get()).data()!;
const balance = async (uid: string) => (await db.collection("users").doc(uid).get()).get("balance") as number;
const level = async () => ((await db.collection("tank").doc("main").get()).get("liters") as number | undefined) ?? 0;
const tankLines = async (flightId: string) =>
  (await db.collection("tankMovements").where("flightId", "==", flightId).get()).docs.map((d) => d.data());
const flightTx = async (flightId: string) =>
  (await db.collection("transactions").where("flightId", "==", flightId).get()).docs.map((d) => d.data());
const supplyTx = async (flightId: string) => (await flightTx(flightId)).filter((t) => t.type === "fuel_supply");
const cashLines = async () => (await db.collection("cashMovements").get()).size;

/** Vol valide passé (90 min prévues), prêt à être clôturé. */
async function pastFlight(fields: Record<string, unknown>): Promise<{ id: string; start: number }> {
  const start = Date.now() - 3 * H;
  const id = await seedFlight({
    start, end: start + 90 * 60_000, status: "valide", pricingMode: "standard", ...fields,
  });
  return { id, start };
}

const close = (caller: { uid: string; token: { email_verified?: boolean } }, id: string, o: Record<string, unknown>) =>
  closeFlight(caller, { ...FUEL, landings: 1, flightId: id, actualMinutes: 90, ...o });

/** Données d'une correction : l'état courant du vol, modifié par `o`. */
async function correction(id: string, o: Record<string, unknown> = {}) {
  const f = await getFlight(id);
  return {
    flightId: id,
    start: (f.start as admin.firestore.Timestamp).toMillis(),
    end: (f.end as admin.firestore.Timestamp).toMillis(),
    destination: f.destination, aircraftId: f.aircraftId, crew: f.crew, passengers: f.passengers,
    instruction: f.instruction === true, baptism: f.pricingMode === "baptism", baptismTier: f.baptismTier ?? null,
    ...o,
  };
}

test("clôture « Aucun » : aucun mouvement de cuve ni crédit, provenance à zéro", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const { id } = await pastFlight({ crew: [pilot.uid], aircraftId: a });
  await close(pilot, id, {});
  assert.deepEqual(await tankLines(id), []);
  assert.deepEqual(await supplyTx(id), []);
  assert.equal(await level(), 0);
  const f = await getFlight(id);
  assert.deepEqual(
    [f.fuelAddedLiters, f.fuelFromTankLiters, f.fuelFromPersonalLiters, f.fuelSupplierUid, f.fuelSupplyCredit],
    [0, 0, 0, null, 0]);
});

test("clôture cuve 20 L : cuve −20, ligne « flight » du jour du vol, non technique", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const { id, start } = await pastFlight({ crew: [pilot.uid], aircraftId: a });
  await close(pilot, id, { fuelFromTank: 20 });
  assert.equal(await level(), -20);
  const lines = await tankLines(id);
  assert.equal(lines.length, 1);
  const l = lines[0];
  assert.equal(l.kind, "flight");
  assert.equal(l.liters, -20);
  assert.equal(l.litersAfter, -20);
  assert.equal(l.aircraftId, a);
  assert.equal(l.technical, false);
  assert.equal(l.date, clubDayString(start));
  assert.equal(l.by, pilot.uid);
  assert.equal(l.cashMovementId, null);
  assert.equal(l.measuredLiters, null);
  const f = await getFlight(id);
  assert.deepEqual([f.fuelAddedLiters, f.fuelFromTankLiters, f.fuelSupplyCredit], [20, 20, 0]);
  assert.deepEqual(await supplyTx(id), []);
});

test("vol technique cuve 15 L : ligne technique, aucun débit", async () => {
  const pilot = await seedUser({ profile: "instructeur", balance: 50_000 });
  const a = await seedAircraft();
  const { id } = await pastFlight({
    crew: [pilot.uid], aircraftId: a, pricingMode: "technical", technical: true, technicalReason: "Essai",
  });
  await close(pilot, id, { fuelFromTank: 15 });
  const lines = await tankLines(id);
  assert.equal(lines.length, 1);
  assert.equal(lines[0].liters, -15);
  assert.equal(lines[0].technical, true);
  assert.equal(await level(), -15);
  assert.equal(await balance(pilot.uid), 50_000);
  assert.deepEqual(await flightTx(id), []);
});

test("bidon perso 20 L à 600 : +12 000 au fournisseur, transaction fuel_supply, caisse inchangée", async () => {
  const payer = await seedUser({ profile: "lache_toute_mission", category: "GAP" });
  const supplier = await seedUser({ profile: "lache_toute_mission", balance: 5_000 });
  const a = await seedAircraft();
  const { id } = await pastFlight({ crew: [payer.uid, supplier.uid], payerUid: payer.uid, aircraftId: a });
  await close(payer, id, { fuelFromPersonal: 20, fuelSupplierUid: supplier.uid });
  assert.equal(await balance(supplier.uid), 17_000);
  assert.equal(await balance(payer.uid), 1_000_000 - 18_000);
  const s = await supplyTx(id);
  assert.equal(s.length, 1);
  assert.equal(s[0].userUid, supplier.uid);
  assert.equal(s[0].amount, 12_000);
  assert.equal(s[0].balanceAfter, 17_000);
  assert.equal(s[0].reason, "Carburant fourni (bidon perso)");
  assert.equal(s[0].by, payer.uid);
  const f = await getFlight(id);
  assert.deepEqual(
    [f.fuelAddedLiters, f.fuelFromTankLiters, f.fuelFromPersonalLiters, f.fuelSupplierUid, f.fuelSupplyCredit],
    [20, 0, 20, supplier.uid, 12_000]);
  assert.equal(await cashLines(), 0);
  assert.equal(await level(), 0);
  assert.deepEqual(await tankLines(id), []);
});

test("« Les deux » 10 + 15 : 25 L ajoutés, cuve −10, crédit 9 000", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const mate = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const a = await seedAircraft();
  const { id } = await pastFlight({ crew: [pilot.uid, mate.uid], payerUid: pilot.uid, aircraftId: a });
  await close(pilot, id, { fuelFromTank: 10, fuelFromPersonal: 15, fuelSupplierUid: mate.uid });
  const f = await getFlight(id);
  assert.equal(f.fuelAddedLiters, 25);
  assert.equal(f.fuelSupplyCredit, 9_000);
  assert.equal(await level(), -10);
  assert.equal(await balance(mate.uid), 9_000);
});

test("fournisseur hors équipage : refusé, rien n'est écrit", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const other = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const a = await seedAircraft();
  const { id } = await pastFlight({ crew: [pilot.uid], aircraftId: a });
  await assert.rejects(
    close(pilot, id, { fuelFromTank: 10, fuelFromPersonal: 20, fuelSupplierUid: other.uid }),
    (e) => code(e) === "invalid-argument" && (e as Error).message === SUPPLIER_OUT);
  assert.equal((await getFlight(id)).isClosed, false);
  assert.equal(await balance(other.uid), 0);
  assert.equal(await level(), 0);
  assert.deepEqual(await flightTx(id), []);
});

test("plein hors vol puis clôture d'un vol plus ancien, cuve 10 L : appareil inchangé, cuve −10", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const pilot = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const { id } = await pastFlight({ crew: [pilot.uid], aircraftId: a });
  await addAircraftFill(instr, { aircraftId: a, liters: 60 });
  await close(pilot, id, { fuelFromTank: 10 });
  assert.equal((await db.collection("aircraft").doc(a).get()).get("fuelLiters"), 60);
  const lines = await tankLines(id);
  assert.equal(lines.length, 1);
  assert.equal(lines[0].liters, -10);
  assert.equal(await level(), -70);
});

test("fournisseur = payeur : débit du vol et crédit enchaînés, solde final exact", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission", category: "GAP", balance: 100_000 });
  const a = await seedAircraft();
  const { id } = await pastFlight({ crew: [pilot.uid], payerUid: pilot.uid, aircraftId: a });
  await close(pilot, id, { fuelFromPersonal: 20, fuelSupplierUid: pilot.uid });
  assert.equal(await balance(pilot.uid), 100_000 - 18_000 + 12_000);
  const txs = await flightTx(id);
  const debit = txs.find((t) => t.type === "flight")!;
  const credit = txs.find((t) => t.type === "fuel_supply")!;
  assert.equal(debit.balanceAfter, 82_000);
  assert.equal(credit.balanceAfter, 94_000);
});

test("fournisseur = instructeur crédité : crédits enchaînés", async () => {
  const instr = await seedUser({ profile: "instructeur", balance: 0 });
  const eleve = await seedUser({ profile: "eleve", category: "GAP", balance: 100_000 });
  const a = await seedAircraft();
  const { id } = await pastFlight({
    crew: [instr.uid, eleve.uid], payerUid: eleve.uid, aircraftId: a, instruction: true,
  });
  await close(instr, id, { fuelFromPersonal: 10, fuelSupplierUid: instr.uid });
  const f = await getFlight(id);
  const instructionCredit = (f.instructionCreditAmount as number | null) ?? 0;
  assert.equal(await balance(instr.uid), instructionCredit + 6_000);
  const credit = (await supplyTx(id))[0];
  assert.equal(credit.balanceAfter, instructionCredit + 6_000);
});

test("correction admin : bidon 20 L DPS → 10 L LDX, cuve 10 → 0", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const dps = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const ldx = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const a = await seedAircraft();
  const { id } = await pastFlight({ crew: [dps.uid, ldx.uid], payerUid: dps.uid, aircraftId: a, createdBy: boss.uid });
  await close(boss, id, { fuelFromTank: 10, fuelFromPersonal: 20, fuelSupplierUid: dps.uid });
  const billed = (await getFlight(id)).billedAmount as number;
  assert.equal(await balance(dps.uid), -billed + 12_000);
  assert.equal(await level(), -10);

  await adminUpdateFlight(boss, await correction(id, {
    fuelFromTank: 0, fuelFromPersonal: 10, fuelSupplierUid: ldx.uid,
  }));

  assert.equal(await balance(dps.uid), -billed);
  assert.equal(await balance(ldx.uid), 6_000);
  const s = (await supplyTx(id)).filter((t) => t.reason === "Régularisation carburant fourni");
  assert.deepEqual(s.map((t) => [t.userUid, t.amount]).sort(),
    [[dps.uid, -12_000], [ldx.uid, 6_000]].sort());
  const adj = (await tankLines(id)).filter((l) => l.kind === "flight_adjustment");
  assert.equal(adj.length, 1);
  assert.equal(adj[0].liters, 10);
  assert.equal(adj[0].by, boss.uid);
  assert.equal(await level(), 0);
  const f = await getFlight(id);
  assert.deepEqual(
    [f.fuelAddedLiters, f.fuelFromTankLiters, f.fuelFromPersonalLiters, f.fuelSupplierUid, f.fuelSupplyCredit],
    [10, 0, 10, ldx.uid, 6_000]);
  // Aucune régularisation de facture : le vol n'a pas changé.
  assert.equal((await flightTx(id)).filter((t) => t.type === "flight_adjustment").length, 0);
});

test("correction admin : crédit recalculé au prix figé du vol", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const p = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const a = await seedAircraft();
  const { id } = await pastFlight({ crew: [p.uid], aircraftId: a, createdBy: boss.uid });
  await close(boss, id, { fuelFromPersonal: 20, fuelSupplierUid: p.uid });
  // Prix figé à 700 F/L (tarif d'alors).
  await db.collection("flights").doc(id).update({ fuelSupplyCredit: 14_000 });
  const before = await balance(p.uid);
  await adminUpdateFlight(boss, await correction(id, { fuelFromTank: 0, fuelFromPersonal: 10, fuelSupplierUid: p.uid }));
  assert.equal(await balance(p.uid), before - 7_000);
  assert.equal((await getFlight(id)).fuelSupplyCredit, 7_000);
});

test("correction admin : provenance inchangée → aucun mouvement", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const p = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const a = await seedAircraft();
  const { id } = await pastFlight({ crew: [p.uid], aircraftId: a, createdBy: boss.uid });
  await close(boss, id, { fuelFromTank: 10, fuelFromPersonal: 20, fuelSupplierUid: p.uid });
  await adminUpdateFlight(boss, await correction(id, { fuelFromTank: 10, fuelFromPersonal: 20, fuelSupplierUid: p.uid }));
  assert.equal((await supplyTx(id)).length, 1);
  assert.equal((await tankLines(id)).length, 1);
  assert.equal(await level(), -10);
});

test("correction admin : fournisseur exclu de l'équipage ou hors équipage corrigé → refus", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const p1 = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const p2 = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const a = await seedAircraft();
  const { id } = await pastFlight({ crew: [p1.uid, p2.uid], payerUid: p1.uid, aircraftId: a, createdBy: boss.uid });
  await close(boss, id, { fuelFromPersonal: 20, fuelSupplierUid: p2.uid });
  await assert.rejects(adminUpdateFlight(boss, await correction(id, { crew: [p1.uid] })),
    (e) => code(e) === "invalid-argument" && (e as Error).message === SUPPLIER_OUT);
  await assert.rejects(adminUpdateFlight(boss, await correction(id, {
    crew: [p1.uid], fuelFromTank: 0, fuelFromPersonal: 20, fuelSupplierUid: p2.uid,
  })), (e) => code(e) === "invalid-argument" && (e as Error).message === SUPPLIER_OUT);
  // Nouvelle provenance sans le fournisseur exclu : acceptée.
  await adminUpdateFlight(boss, await correction(id, {
    crew: [p1.uid], fuelFromTank: 0, fuelFromPersonal: 20, fuelSupplierUid: p1.uid,
  }));
  assert.equal(await balance(p2.uid), 0);
  assert.equal((await getFlight(id)).fuelSupplierUid, p1.uid);
});

test("correction admin : fuelAdded seul refusé sur un vol clôturé avec provenance", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const p = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const { id } = await pastFlight({ crew: [p.uid], aircraftId: a, createdBy: boss.uid });
  await close(boss, id, { fuelFromTank: 10 });
  await assert.rejects(adminUpdateFlight(boss, await correction(id, { fuelAdded: 25 })),
    (e) => code(e) === "invalid-argument" &&
      (e as Error).message === "Carburant ajouté : donnez la provenance (cuve, bidon perso).");
});

test("vol clôturé avant le plan 13 corrigé sans provenance : fuelAdded accepté, aucun mouvement", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const p = await seedUser({ profile: "lache_toute_mission" });
  const a = await seedAircraft();
  const { id } = await pastFlight({ crew: [p.uid], aircraftId: a, createdBy: boss.uid });
  await close(boss, id, {});
  const del = admin.firestore.FieldValue.delete();
  await db.collection("flights").doc(id).update({
    fuelAddedLiters: 20, fuelFromTankLiters: del, fuelFromPersonalLiters: del, fuelSupplierUid: del, fuelSupplyCredit: del,
  });
  const txsBefore = (await flightTx(id)).length;
  await adminUpdateFlight(boss, await correction(id, { fuelAdded: 25 }));
  assert.equal((await getFlight(id)).fuelAddedLiters, 25);
  assert.equal((await flightTx(id)).length, txsBefore);
  assert.deepEqual(await tankLines(id), []);
  // Provenance saisie : écart avec « 0 L cuve, 0 L bidon ».
  await adminUpdateFlight(boss, await correction(id, { fuelFromTank: 5, fuelFromPersonal: 0 }));
  const adj = await tankLines(id);
  assert.equal(adj.length, 1);
  assert.equal(adj[0].kind, "flight_adjustment");
  assert.equal(adj[0].liters, -5);
  assert.equal((await getFlight(id)).fuelAddedLiters, 5);
});

test("suppression admin d'un vol cuve 10 + bidon 20 : cuve +10, crédit −12 000", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const payer = await seedUser({ profile: "lache_toute_mission", category: "GAP", balance: 100_000 });
  const supplier = await seedUser({ profile: "lache_toute_mission", balance: 0 });
  const a = await seedAircraft();
  const { id } = await pastFlight({
    crew: [payer.uid, supplier.uid], payerUid: payer.uid, aircraftId: a, createdBy: boss.uid,
  });
  await close(boss, id, { fuelFromTank: 10, fuelFromPersonal: 20, fuelSupplierUid: supplier.uid });
  assert.equal(await level(), -10);
  assert.equal(await balance(supplier.uid), 12_000);

  await adminDeleteFlight(boss, { flightId: id });

  assert.equal(await level(), 0);
  const adj = (await tankLines(id)).filter((l) => l.kind === "flight_adjustment");
  assert.equal(adj.length, 1);
  assert.equal(adj[0].liters, 10);
  assert.equal(await balance(supplier.uid), 0);
  const reg = (await supplyTx(id)).filter((t) => t.amount < 0);
  assert.equal(reg.length, 1);
  assert.equal(reg[0].amount, -12_000);
  assert.equal(reg[0].reason, "Régularisation carburant fourni");
  assert.equal(await balance(payer.uid), 100_000);
  assert.equal((await getFlight(id)).deleted, true);
});

test("suppression admin : fournisseur = payeur, remboursement et reprise enchaînés", async () => {
  const boss = await seedUser({ profile: null, isAdmin: true });
  const p = await seedUser({ profile: "lache_toute_mission", category: "GAP", balance: 100_000 });
  const a = await seedAircraft();
  const { id } = await pastFlight({ crew: [p.uid], payerUid: p.uid, aircraftId: a, createdBy: boss.uid });
  await close(boss, id, { fuelFromPersonal: 20, fuelSupplierUid: p.uid });
  assert.equal(await balance(p.uid), 94_000);
  await adminDeleteFlight(boss, { flightId: id });
  assert.equal(await balance(p.uid), 100_000);
});
