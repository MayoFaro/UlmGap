// Lancé par `npm run test:int` (émulateurs Auth + Firestore, projet demo-ulmgap).
import { test } from "node:test";
import * as assert from "node:assert/strict";
import * as admin from "firebase-admin";

if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT ?? "demo-ulmgap" });
}
import { createUser, updateUser } from "./users";
import { upsertAircraft } from "./aircraft";
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
