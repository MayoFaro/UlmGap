// Lancé par `npm run test:int` (émulateurs Auth + Firestore).
// Crédit et correction de compte par un instructeur ou un admin (task 5) :
// mouvement, historique, verrou et accès réservé au personnel.
import { test } from "node:test";
import * as assert from "node:assert/strict";
import {
  code, db, seedAircraft, seedFlight, seedUser, H,
} from "../flights/testkit";
import { creditAccount, correctAccount } from "./accounts";
import { closeFlight } from "../flights/close";

const getUser = async (uid: string) => (await db.collection("users").doc(uid).get()).data()!;
const userTx = async (uid: string) => {
  const snap = await db.collection("transactions").where("userUid", "==", uid).get();
  return snap.docs.map((d) => d.data());
};

test("crédit de 50 000 par un instructeur : solde +50 000, transaction credit", async () => {
  const instr = await seedUser({ profile: "instructeur" });
  const target = await seedUser({ profile: "eleve", balance: 100_000 });

  const r = await creditAccount(instr, { userUid: target.uid, amount: 50_000, reason: "Versement" });
  assert.deepEqual(r, { balance: 150_000 });

  assert.equal((await getUser(target.uid)).balance, 150_000);
  const txs = await userTx(target.uid);
  assert.equal(txs.length, 1);
  assert.equal(txs[0].type, "credit");
  assert.equal(txs[0].amount, 50_000);
  assert.equal(txs[0].balanceAfter, 150_000);
  assert.equal(txs[0].by, instr.uid);
  assert.equal(txs[0].reason, "Versement");
  assert.equal(txs[0].flightId, null);
  assert.ok(txs[0].at);
});

test("crédit de 1 000 000 (aucun plafond) accepté", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const target = await seedUser({ profile: "eleve", balance: 0 });
  const r = await creditAccount(admin1, { userUid: target.uid, amount: 1_000_000 });
  assert.deepEqual(r, { balance: 1_000_000 });
});

test("correction de −10 000 avec motif par un admin : solde et transaction correction", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const target = await seedUser({ profile: "eleve", balance: 100_000 });

  const r = await correctAccount(admin1, { userUid: target.uid, amount: -10_000, reason: "Erreur de saisie" });
  assert.deepEqual(r, { balance: 90_000 });

  assert.equal((await getUser(target.uid)).balance, 90_000);
  const txs = await userTx(target.uid);
  assert.equal(txs.length, 1);
  assert.equal(txs[0].type, "correction");
  assert.equal(txs[0].amount, -10_000);
  assert.equal(txs[0].balanceAfter, 90_000);
  assert.equal(txs[0].by, admin1.uid);
  assert.equal(txs[0].reason, "Erreur de saisie");
});

test("correction sans motif : invalid-argument", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  const target = await seedUser({ profile: "eleve", balance: 100_000 });
  await assert.rejects(
    correctAccount(admin1, { userUid: target.uid, amount: -10_000 }),
    (e) => code(e) === "invalid-argument",
  );
});

test("un lâché (ni instructeur ni admin) : permission-denied, pour créditer et pour corriger", async () => {
  const lache = await seedUser({ profile: "lache_toute_mission" });
  const target = await seedUser({ profile: "eleve", balance: 100_000 });
  await assert.rejects(
    creditAccount(lache, { userUid: target.uid, amount: 10_000 }),
    (e) => code(e) === "permission-denied" &&
      (e as Error).message === "Réservé aux instructeurs et aux admins.",
  );
  await assert.rejects(
    correctAccount(lache, { userUid: target.uid, amount: -10_000, reason: "Motif" }),
    (e) => code(e) === "permission-denied",
  );
  assert.equal((await getUser(target.uid)).balance, 100_000);
});

test("compte cible introuvable : not-found", async () => {
  const admin1 = await seedUser({ profile: null, isAdmin: true });
  await assert.rejects(
    creditAccount(admin1, { userUid: "inconnu-xyz", amount: 10_000 }),
    (e) => code(e) === "not-found",
  );
});

test("un crédit et une clôture simultanés sur le même compte : solde final et historique cohérents", async () => {
  const pilot = await seedUser({ profile: "lache_toute_mission", category: "GAP", balance: 1_000_000 });
  const instr = await seedUser({ profile: "instructeur" });
  const aircraft = await seedAircraft();
  const flightId = await seedFlight({
    start: Date.now() - 2 * H, end: Date.now() - H, crew: [pilot.uid], aircraftId: aircraft,
    status: "valide", pricingMode: "standard",
  });

  const results = await Promise.allSettled([
    creditAccount(instr, { userUid: pilot.uid, amount: 50_000, reason: "Versement" }),
    closeFlight(pilot, { flightId, actualMinutes: 90 }),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 2);

  // GAP 90 min = 15 000 (spec §2.4 : flatFee 12 000 pour 75 min incluses + 15 min à 12 000/h).
  const expectedBalance = 1_000_000 + 50_000 - 15_000;
  assert.equal((await getUser(pilot.uid)).balance, expectedBalance);

  const txs = (await userTx(pilot.uid)).sort((a, b) => (a.balanceAfter as number) - (b.balanceAfter as number));
  assert.equal(txs.length, 2);
  // Les deux mouvements se sérialisent (verrou flightLocks/user_<pilot>) : le
  // second balanceAfter part du solde réellement laissé par le premier, pas
  // d'un solde lu avant l'autre transaction.
  const [first, second] = txs;
  assert.equal(second.balanceAfter, expectedBalance);
  assert.equal(first.balanceAfter + (first.type === "credit" ? -50_000 : 15_000), 1_000_000);
  assert.equal(second.balanceAfter, first.balanceAfter + (second.type === "credit" ? 50_000 : -15_000));
});
