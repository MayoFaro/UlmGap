// Lancé par `npm run test:int` (émulateurs Auth + Firestore).
// Caisse (spec §11) : opérations, corrections, écart, reprise.
import { afterEach, beforeEach, test } from "node:test";
import * as assert from "node:assert/strict";
import { code, db, resetCashbox, resetTank, seedUser } from "../flights/testkit";
import { formatFcfa } from "../rules/pricing";
import { creditAccount } from "./accounts";
import { addCashMovement, closeMigration, correctCashMovement } from "./cash";

beforeEach(async () => { await resetCashbox(); await resetTank(); });
afterEach(async () => { await resetCashbox(); await resetTank(); });

const balance = async () => ((await db.collection("cashbox").doc("main").get()).get("balance") as number) ?? 0;
const line = async (id: string) => (await db.collection("cashMovements").doc(id).get()).data()!;
const userBalance = async (uid: string) => (await db.collection("users").doc(uid).get()).get("balance") as number;
const fuelCreditLine = async (uid: string) =>
  (await db.collection("cashMovements").where("userUid", "==", uid).where("correctsId", "==", null).get()).docs[0];

test("achat carburant par un instructeur : sortie de caisse, ligne non modifiable", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  await addCashMovement(instr, { kind: "off_app_income", amount: 100_000, note: "Baptême" });
  const r = await addCashMovement(instr, { kind: "fuel_purchase", amount: 30_000, date: "2026-10-12" });
  assert.equal(r.balance, 70_000);
  assert.equal(await balance(), 70_000);
  const l = await line(r.id);
  assert.equal(l.kind, "fuel_purchase");
  assert.equal(l.amount, -30_000);
  assert.equal(l.date, "2026-10-12");
  assert.equal(l.balanceAfter, 70_000);
  assert.equal(l.by, instr.uid);
});

test("écart de caisse : refusé à un instructeur, accepté pour un admin", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  await assert.rejects(addCashMovement(instr, { kind: "cash_gap", amount: -2_000, note: "Comptage" }),
    (e) => code(e) === "permission-denied");
  const r = await addCashMovement(admin1, { kind: "cash_gap", amount: -2_000, note: "Comptage" });
  assert.equal(r.balance, -2_000);
});

test("un lâché : aucune opération de caisse", async () => {
  const lache = await seedUser({ profile: "lache_toute_mission" });
  await assert.rejects(addCashMovement(lache, { kind: "fuel_purchase", amount: 1_000 }),
    (e) => code(e) === "permission-denied");
});

test("deux opérations simultanées : solde et balanceAfter enchaînés", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const [a, b] = await Promise.all([
    addCashMovement(instr, { kind: "off_app_income", amount: 70_000, note: "Baptême A" }),
    addCashMovement(instr, { kind: "off_app_income", amount: 90_000, note: "Baptême B" }),
  ]);
  assert.equal(await balance(), 160_000);
  // L'ordre de validation n'est pas fixé : le premier solde est 70 000 ou 90 000, le second 160 000.
  const [first, second] = [a.balance, b.balance].sort((x, y) => x - y);
  assert.ok(first === 70_000 || first === 90_000);
  assert.equal(second, 160_000);
});

test("correction d'une dépense : écart en ligne de correction, même date ; successives ; zéro annule", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const r = await addCashMovement(instr, { kind: "maintenance", amount: 86_000, note: "Roue", date: "2026-07-21" });
  const c1 = await correctCashMovement(instr, { movementId: r.id, amount: 68_000, note: "Faute de frappe" });
  const l1 = await line(c1.id);
  assert.equal(l1.kind, "maintenance");
  assert.equal(l1.amount, 18_000);
  assert.equal(l1.correctsId, r.id);
  assert.equal(l1.date, "2026-07-21");
  assert.equal(l1.note, "Correction : Faute de frappe");
  assert.equal(await balance(), -68_000);

  const c2 = await correctCashMovement(instr, { movementId: r.id, amount: 0 });
  assert.equal((await line(c2.id)).amount, 68_000);
  assert.equal((await line(c2.id)).note, "Correction");
  assert.equal(await balance(), 0);

  await assert.rejects(correctCashMovement(instr, { movementId: r.id, amount: 0 }),
    (e) => code(e) === "failed-precondition");
  await assert.rejects(correctCashMovement(instr, { movementId: c1.id, amount: 1_000 }),
    (e) => code(e) === "failed-precondition" &&
      (e as Error).message === "Corrigez l'opération d'origine, pas une correction.");
});

test("correction d'un Crédit carburant : caisse et compte régularisés, sur le solde actuel du compte", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const pilot = await seedUser({ profile: "eleve", balance: 0 });
  await creditAccount(instr, { userUid: pilot.uid, amount: 50_000, date: "2026-10-12" });
  await addCashMovement(instr, { kind: "fuel_purchase", amount: 10_000 });
  await db.collection("users").doc(pilot.uid).update({ balance: 38_000 }); // un vol entre-temps
  const original = await fuelCreditLine(pilot.uid);

  await correctCashMovement(instr, { movementId: original.id, amount: 5_000 });

  assert.equal(await balance(), 5_000 - 10_000);
  assert.equal(await userBalance(pilot.uid), 38_000 - 45_000);
  const txs = (await db.collection("transactions").where("userUid", "==", pilot.uid).get()).docs.map((d) => d.data());
  const fix = txs.find((t) => t.amount === -45_000)!;
  assert.equal(fix.type, "credit");
  assert.equal(fix.reason, "Correction crédit carburant du 12/10/2026");
});

test("Fond initial et écart : correction réservée aux admins", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const gap = await addCashMovement(admin1, { kind: "cash_gap", amount: 5_000, note: "Comptage" });
  await assert.rejects(correctCashMovement(instr, { movementId: gap.id, amount: 4_000 }),
    (e) => code(e) === "permission-denied");
  const opening = db.collection("cashMovements").doc();
  await opening.set({ kind: "opening", amount: 1_000, date: "2025-03-05", correctsId: null, userUid: null });
  await assert.rejects(correctCashMovement(instr, { movementId: opening.id, amount: 2_000 }),
    (e) => code(e) === "permission-denied");
  await correctCashMovement(admin1, { movementId: opening.id, amount: 2_000 });
});

test("Écart de caisse : message de montant inchangé gardant le signe", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const gap = await addCashMovement(admin1, { kind: "cash_gap", amount: -2_000, note: "Comptage" });
  await assert.rejects(correctCashMovement(admin1, { movementId: gap.id, amount: -2_000 }),
    (e) => code(e) === "failed-precondition" &&
      (e as Error).message === `Le montant est déjà de ${formatFcfa(-2_000)}.`);
});

test("opération introuvable : not-found", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  await assert.rejects(correctCashMovement(instr, { movementId: "absent", amount: 1 }),
    (e) => code(e) === "not-found");
});

test("Reprise terminée : admin seulement, une seule fois, solde conservé", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  await addCashMovement(instr, { kind: "off_app_income", amount: 70_000, note: "Baptême" });
  await assert.rejects(closeMigration(instr), (e) => code(e) === "permission-denied");
  await closeMigration(admin1);
  const box = (await db.collection("cashbox").doc("main").get()).data()!;
  assert.ok(box.migrationClosedAt);
  assert.equal(box.balance, 70_000);
  await assert.rejects(closeMigration(admin1),
    (e) => code(e) === "failed-precondition" && (e as Error).message === "La reprise est déjà terminée.");
});

test("achat carburant avec 500 L : caisse -montant, cuve +500, lignes jumelles", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  await addCashMovement(instr, { kind: "off_app_income", amount: 400_000, note: "Baptême" });
  const r = await addCashMovement(instr, {
    kind: "fuel_purchase", amount: 300_000, liters: 500, date: "2026-10-12", note: "Total",
  });
  assert.equal(await balance(), 100_000);
  const tank = await db.collection("tank").doc("main").get();
  assert.equal(tank.get("liters"), 500);
  const m = (await db.collection("tankMovements").get()).docs;
  assert.equal(m.length, 1);
  assert.equal(m[0].get("kind"), "refill");
  assert.equal(m[0].get("liters"), 500);
  assert.equal(m[0].get("litersAfter"), 500);
  assert.equal(m[0].get("cashMovementId"), r.id);
  assert.equal(m[0].get("date"), "2026-10-12");
  assert.equal(m[0].get("note"), "Total");
  assert.equal(m[0].get("by"), instr.uid);
});

test("achat carburant sans litres : cuve inchangée", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  await addCashMovement(instr, { kind: "fuel_purchase", amount: 30_000 });
  assert.equal((await db.collection("tankMovements").get()).size, 0);
  assert.equal((await db.collection("tank").doc("main").get()).exists, false);
});
