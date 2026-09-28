// Lancé par `npm run test:int` (émulateurs Auth + Firestore, projet demo-ulmgap).
import { test } from "node:test";
import * as assert from "node:assert/strict";
import * as admin from "firebase-admin";

if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT ?? "demo-ulmgap" });
}
import { createUser, updateUser } from "./users";
import { upsertAircraft } from "./aircraft";
import { bootstrapAdmin } from "./bootstrap";
import { seedTestUsers, TEST_ACCOUNTS } from "./seed";
import type { Caller } from "../auth/guards";

const db = admin.firestore();
const uniq = () => Math.random().toString(36).slice(2, 8);
const code = (e: unknown) => (e as { code?: string }).code;

async function seedUser(uid: string, fields: Record<string, unknown>): Promise<Caller> {
  await db.collection("users").doc(uid).set({ active: true, isAdmin: false, ...fields });
  return { uid, token: { email_verified: true } };
}
const newUser = () => ({
  email: `p-${uniq()}@club.fr`, displayName: "Jean Dupont", shortName: "JDU",
  profile: "eleve", category: "EXT",
});

test("non-admin : permission-denied (appel direct, hors UI)", async () => {
  const me = await seedUser(`u-${uniq()}`, {});
  await assert.rejects(createUser(me, newUser()), (e) => code(e) === "permission-denied");
});

test("admin à e-mail non vérifié : permission-denied", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  await assert.rejects(createUser({ ...me, token: { email_verified: false } }, newUser()),
    (e) => code(e) === "permission-denied");
});

test("admin désactivé : permission-denied", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true, active: false });
  await assert.rejects(createUser(me, newUser()), (e) => code(e) === "permission-denied");
});

test("création : Auth, users et profiles cohérents", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  const input = newUser();
  const { uid } = await createUser(me, input);
  const rec = await admin.auth().getUser(uid);
  assert.equal(rec.email, input.email);
  const u = (await db.collection("users").doc(uid).get()).data()!;
  assert.equal(u.shortName, "JDU");
  assert.equal(u.balance, 0);
  assert.equal(u.isAdmin, false);
  const p = (await db.collection("profiles").doc(uid).get()).data()!;
  assert.deepEqual(p, { displayName: "Jean Dupont", shortName: "JDU", profile: "eleve", active: true });
});

test("e-mail déjà utilisé : already-exists, aucun document orphelin", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  const input = newUser();
  await createUser(me, input);
  const before = (await db.collection("users").where("email", "==", input.email).get()).size;
  await assert.rejects(createUser(me, input), (e) => code(e) === "already-exists");
  const after = (await db.collection("users").where("email", "==", input.email).get()).size;
  assert.equal(after, before);
});

test("entrée invalide : invalid-argument", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  await assert.rejects(createUser(me, { ...newUser(), category: "XX" }),
    (e) => code(e) === "invalid-argument");
});

test("désactivation : Auth disabled et profiles.active à false", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  const { uid } = await createUser(me, newUser());
  await updateUser(me, { uid, active: false, category: "MIL" });
  assert.equal((await admin.auth().getUser(uid)).disabled, true);
  assert.equal((await db.collection("profiles").doc(uid).get()).get("active"), false);
  assert.equal((await db.collection("users").doc(uid).get()).get("category"), "MIL");
});

test("un admin ne peut ni se retirer ses droits ni se désactiver", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  await assert.rejects(updateUser(me, { uid: me.uid, isAdmin: false }),
    (e) => code(e) === "failed-precondition");
  await assert.rejects(updateUser(me, { uid: me.uid, active: false }),
    (e) => code(e) === "failed-precondition");
});

test("mise à jour d'un compte inexistant : not-found", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  await assert.rejects(updateUser(me, { uid: "nope", category: "GR" }),
    (e) => code(e) === "not-found");
});

test("appareils : création, modification, immatriculation en double refusée", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  const reg = `F-${uniq().toUpperCase().slice(0, 4)}`;
  const { id } = await upsertAircraft(me, { registration: reg, label: "ULM 1" });
  await upsertAircraft(me, { id, registration: reg, label: "ULM 1 bis", active: false });
  const a = (await db.collection("aircraft").doc(id).get()).data()!;
  assert.equal(a.label, "ULM 1 bis");
  assert.equal(a.active, false);
  await assert.rejects(upsertAircraft(me, { registration: reg, label: "Autre" }),
    (e) => code(e) === "already-exists");
});

test("I2 : compte Auth orphelin (sans users) : repris au lieu de bloquer", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  const input = newUser();
  const orphan = await admin.auth().createUser({ email: input.email });
  const { uid } = await createUser(me, input);
  assert.equal(uid, orphan.uid);
  assert.equal((await db.collection("users").doc(uid).get()).get("shortName"), "JDU");
  assert.equal((await db.collection("profiles").doc(uid).get()).get("active"), true);
  assert.equal((await admin.auth().getUser(uid)).displayName, "Jean Dupont");
});

test("M3 : si Auth échoue, Firestore reste inchangé", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  // Document users sans compte Auth : admin.auth().updateUser échoue.
  const uid = `ghost-${uniq()}`;
  await db.collection("users").doc(uid).set({
    displayName: "Fantôme", shortName: "FAN", profile: null, category: "GAP",
    isAdmin: false, active: true, email: "f@x.fr", balance: 0,
  });
  await assert.rejects(updateUser(me, { uid, active: false }));
  assert.equal((await db.collection("users").doc(uid).get()).get("active"), true);
});

test("M3 : réactivation : Auth et Firestore réactivés", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  const { uid } = await createUser(me, newUser());
  await updateUser(me, { uid, active: false });
  await updateUser(me, { uid, active: true });
  assert.equal((await admin.auth().getUser(uid)).disabled, false);
  assert.equal((await db.collection("users").doc(uid).get()).get("active"), true);
  assert.equal((await db.collection("profiles").doc(uid).get()).get("active"), true);
});

test("M4 : compte sans profiles : le document créé est complet", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  const rec = await admin.auth().createUser({ email: `old-${uniq()}@club.fr` });
  await db.collection("users").doc(rec.uid).set({
    displayName: "Ancien", shortName: "ANC", profile: "eleve", category: "EXT",
    isAdmin: false, active: true, email: rec.email, balance: 0,
  });
  await updateUser(me, { uid: rec.uid, category: "GR" });
  assert.deepEqual((await db.collection("profiles").doc(rec.uid).get()).data(),
    { displayName: "Ancien", shortName: "ANC", profile: "eleve", active: true });
});

test("M7 : deux créations simultanées de la même immatriculation : une seule passe", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  const reg = `F-${uniq().toUpperCase().slice(0, 4)}`;
  const r = await Promise.allSettled([
    upsertAircraft(me, { registration: reg, label: "A" }),
    upsertAircraft(me, { registration: reg, label: "B" }),
  ]);
  assert.equal(r.filter((x) => x.status === "fulfilled").length, 1);
  assert.equal((await db.collection("aircraft").where("registration", "==", reg).get()).size, 1);
});

test("M7 : changer d'immatriculation libère l'ancienne", async () => {
  const me = await seedUser(`a-${uniq()}`, { isAdmin: true });
  const a = `F-${uniq().toUpperCase().slice(0, 4)}`;
  const b = `F-${uniq().toUpperCase().slice(0, 4)}`;
  const { id } = await upsertAircraft(me, { registration: a, label: "ULM" });
  await upsertAircraft(me, { id, registration: b, label: "ULM" });
  await upsertAircraft(me, { registration: a, label: "Autre" }); // ne lève pas
  assert.equal((await db.collection("aircraftRegistrations").doc(b).get()).get("aircraftId"), id);
});

test("M8 : bootstrap sur un admin existant : ni solde, ni catégorie, ni createdAt écrasés", async () => {
  const email = `boot-${uniq()}@club.fr`;
  const rec = await admin.auth().createUser({ email });
  const createdAt = admin.firestore.Timestamp.fromMillis(1_700_000_000_000);
  await db.collection("users").doc(rec.uid).set({
    email, displayName: "Chef", shortName: "CHF", profile: "instructeur", category: "MIL",
    isAdmin: false, active: true, balance: 5000, createdAt,
  });
  const uid = await bootstrapAdmin(admin.auth(), db, { email, name: "Autre", short: "XYZ" });
  const u = (await db.collection("users").doc(uid).get()).data()!;
  assert.equal(uid, rec.uid);
  assert.equal(u.isAdmin, true);
  assert.equal(u.balance, 5000);
  assert.equal(u.category, "MIL");
  assert.equal(u.shortName, "CHF");
  assert.ok((u.createdAt as admin.firestore.Timestamp).isEqual(createdAt));
});

test("M8 : bootstrap d'un existant sans profiles : profil complet écrit", async () => {
  const email = `boot-${uniq()}@club.fr`;
  const rec = await admin.auth().createUser({ email });
  await db.collection("users").doc(rec.uid).set({
    email, displayName: "Sans Profil", shortName: "SPR", profile: "eleve", category: "GAP",
    isAdmin: false, active: true, balance: 0,
  });
  const uid = await bootstrapAdmin(admin.auth(), db, { email, name: "Autre", short: "XYZ" });
  assert.equal(uid, rec.uid);
  assert.deepEqual((await db.collection("profiles").doc(uid).get()).data(),
    { displayName: "Sans Profil", shortName: "SPR", profile: "eleve", active: true });
});

test("M8 : bootstrap d'un existant avec profiles déjà présent : simple fusion active", async () => {
  const email = `boot-${uniq()}@club.fr`;
  const rec = await admin.auth().createUser({ email });
  await db.collection("users").doc(rec.uid).set({
    email, displayName: "Avec Profil", shortName: "AVP", profile: "eleve", category: "GAP",
    isAdmin: false, active: true, balance: 0,
  });
  await db.collection("profiles").doc(rec.uid).set({
    displayName: "Ancien Nom", shortName: "OLD", profile: "instructeur", active: false,
  });
  const uid = await bootstrapAdmin(admin.auth(), db, { email, name: "Autre", short: "XYZ" });
  assert.deepEqual((await db.collection("profiles").doc(uid).get()).data(),
    { displayName: "Ancien Nom", shortName: "OLD", profile: "instructeur", active: true });
});

test("M8 : bootstrap d'un nouvel admin : users et profiles complets", async () => {
  const email = `boot-${uniq()}@club.fr`;
  const uid = await bootstrapAdmin(admin.auth(), db, { email, name: "Neuf", short: "NEU" });
  const u = (await db.collection("users").doc(uid).get()).data()!;
  assert.equal(u.isAdmin, true);
  assert.equal(u.balance, 0);
  assert.ok(u.createdAt);
  assert.deepEqual((await db.collection("profiles").doc(uid).get()).data(),
    { displayName: "Neuf", shortName: "NEU", profile: null, active: true });
});

test("seedTestUsers : crée 8 comptes vérifiés, avec documents users et profiles complets", async () => {
  const emails = await seedTestUsers(admin.auth(), db, "password1234");
  assert.equal(emails.length, 8);
  for (const account of TEST_ACCOUNTS) {
    const email = `test-${account.code}@ulmgap.invalid`;
    assert.ok(emails.includes(email));
    const rec = await admin.auth().getUserByEmail(email);
    assert.equal(rec.emailVerified, true);
    assert.equal(rec.disabled, false);
    const u = (await db.collection("users").doc(rec.uid).get()).data()!;
    assert.equal(u.email, email);
    assert.equal(u.displayName, account.name);
    assert.equal(u.shortName, account.short);
    assert.equal(u.profile, account.profile);
    assert.equal(u.category, account.category);
    assert.equal(u.isAdmin, false);
    assert.equal(u.active, true);
    assert.equal(u.balance, 0);
    const p = (await db.collection("profiles").doc(rec.uid).get()).data()!;
    assert.deepEqual(p, {
      displayName: account.name, shortName: account.short, profile: account.profile, active: true,
    });
  }
});

test("seedTestUsers : une relance conserve un balance modifié entre-temps", async () => {
  await seedTestUsers(admin.auth(), db, "password1234");
  const email = `test-${TEST_ACCOUNTS[0].code}@ulmgap.invalid`;
  const { uid } = await admin.auth().getUserByEmail(email);
  await db.collection("users").doc(uid).update({ balance: 4242 });
  const emails = await seedTestUsers(admin.auth(), db, "newpassword1");
  assert.equal(emails.length, 8);
  assert.equal((await db.collection("users").doc(uid).get()).get("balance"), 4242);
  const rec = await admin.auth().getUser(uid);
  assert.equal(rec.emailVerified, true);
  assert.equal(rec.disabled, false);
});
