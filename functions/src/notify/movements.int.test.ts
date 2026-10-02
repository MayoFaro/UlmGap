// Lancé par `npm run test:int` : notifications des mouvements de crédit
// (spec §6.1), FCM remplacé par une doublure qui enregistre les envois. La
// base de l'émulateur est partagée entre fichiers : d'autres instructeurs y
// existent, d'où des vérifications d'inclusion plutôt que d'égalité.
import { test, beforeEach, afterEach } from "node:test";
import * as assert from "node:assert/strict";
import * as admin from "firebase-admin";
import { db, FUEL, H, seedAircraft, seedFlight, seedUser } from "../flights/testkit";
import { correctAccount, creditAccount } from "../finance/accounts";
import { closeFlight } from "../flights/close";
import { adminUpdateFlight } from "../flights/admin-edit";
import { formatFcfa } from "../rules/pricing";
import { PushMessage } from "../rules/notifications";
import { setPushSenderForTests } from "./push";

type Sent = { tokens: string[]; message: PushMessage };
let sent: Sent[] = [];

beforeEach(() => {
  sent = [];
  setPushSenderForTests(async (tokens, message) => {
    sent.push({ tokens, message });
    return { failedTokens: [], invalidTokens: [] };
  });
});
afterEach(() => setPushSenderForTests(null));

async function user(profile: string | null, shortName: string, o: { isAdmin?: boolean; balance?: number } = {}) {
  const u = await seedUser({ profile, shortName, ...o });
  await db.collection("users").doc(u.uid).update({ fcmToken: `tok-${u.uid}` });
  await db.collection("profiles").doc(u.uid).set({ shortName, displayName: shortName, profile, active: true });
  return u;
}
const tok = (u: { uid: string }) => `tok-${u.uid}`;
const about = (name: string) => sent.filter((s) => s.message.title === `Compte de ${name}`);

test("crédit : l'intéressé et les autres instructeurs, pas l'auteur", async () => {
  const a = await user("instructeur", "INA");
  const b = await user("instructeur", "INB");
  const ldx = await user("eleve", "LDX", { balance: 70_000 });
  await creditAccount(a, { userUid: ldx.uid, amount: 50_000 });
  const m = about("LDX");
  assert.equal(m.length, 1);
  assert.equal(m[0].message.body,
    `Crédit : +${formatFcfa(50_000)}. Nouveau solde : ${formatFcfa(120_000)}.`);
  assert.ok(m[0].tokens.includes(tok(ldx)));
  assert.ok(m[0].tokens.includes(tok(b)));
  assert.ok(!m[0].tokens.includes(tok(a)));
});

test("correction : montant négatif signé", async () => {
  const a = await user("instructeur", "INC");
  const ldx = await user("eleve", "LDY", { balance: 100_000 });
  await correctAccount(a, { userUid: ldx.uid, newBalance: 90_000, reason: "Erreur" });
  assert.equal(about("LDY")[0].message.body,
    `Correction : ${formatFcfa(-10_000)}. Nouveau solde : ${formatFcfa(90_000)}.`);
});

test("instructeur qui crédite son propre compte : rien pour lui", async () => {
  const a = await user("instructeur", "INS");
  const b = await user("instructeur", "INT");
  await creditAccount(a, { userUid: a.uid, amount: 10_000 });
  const m = about("INS")[0];
  assert.ok(!m.tokens.includes(tok(a)));
  assert.ok(m.tokens.includes(tok(b)));
});

test("correction admin d'un vol clôturé : « Régularisation » ; clôture seule : rien", async () => {
  const boss = await user(null, "ADM", { isAdmin: true });
  const pilot = await user("lache_toute_mission", "PIL");
  await db.collection("users").doc(pilot.uid).update({ category: "GAP" });
  const a = await seedAircraft();
  const start = Date.now() - 3 * H;
  const id = await seedFlight({
    start, end: start + 90 * 60_000, crew: [pilot.uid], aircraftId: a, createdBy: boss.uid,
  });
  await closeFlight(pilot, { ...FUEL, flightId: id, actualMinutes: 90, landings: 1 });
  assert.deepEqual(about("PIL"), []); // débit de clôture : pas un mouvement de crédit

  const f = (await db.collection("flights").doc(id).get()).data()!;
  await adminUpdateFlight(boss, {
    flightId: id,
    start: (f.start as admin.firestore.Timestamp).toMillis(),
    end: (f.end as admin.firestore.Timestamp).toMillis(),
    destination: f.destination, aircraftId: f.aircraftId, crew: f.crew, passengers: f.passengers,
    actualMinutes: 120,
  });
  const m = about("PIL");
  assert.equal(m.length, 1);
  assert.ok(m[0].message.body.startsWith(`Régularisation : ${formatFcfa(-6_000)}.`));
  assert.ok(m[0].tokens.includes(tok(pilot)));
});
