import { test } from "node:test";
import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  CATEGORIES, PROFILES, ValidationError,
  validateAircraft, validateNewUser, validateUserPatch,
} from "./validation";

const ref = JSON.parse(fs.readFileSync(
  path.resolve(__dirname, "../../../test/fixtures/referentials.json"), "utf8"));

test("référentiels = fixture partagée avec Dart", () => {
  assert.deepEqual([...PROFILES], ref.profiles);
  assert.deepEqual([...CATEGORIES], ref.categories);
});

const ok = {
  email: " Pilote@Club.FR ", displayName: " Jean Dupont ", shortName: "jdu",
  profile: "eleve", category: "EXT",
};

test("validateNewUser : normalise et applique les défauts", () => {
  assert.deepEqual(validateNewUser(ok), {
    email: "pilote@club.fr", displayName: "Jean Dupont", shortName: "JDU",
    profile: "eleve", category: "EXT", isAdmin: false, active: true,
    amphibiousCleared: false,
  });
});

test("validateNewUser : amphibiousCleared accepté, non booléen refusé", () => {
  assert.equal(validateNewUser({ ...ok, amphibiousCleared: true }).amphibiousCleared, true);
  assert.throws(() => validateNewUser({ ...ok, amphibiousCleared: "oui" }), ValidationError);
});

test("validateUserPatch : amphibiousCleared seul accepté", () => {
  assert.deepEqual(validateUserPatch({ uid: "u1", amphibiousCleared: true }),
    { uid: "u1", patch: { amphibiousCleared: true } });
  assert.throws(() => validateUserPatch({ uid: "u1", amphibiousCleared: 1 }), ValidationError);
});

test("validateNewUser : profil null accepté (gestionnaire non pilote)", () => {
  assert.equal(validateNewUser({ ...ok, profile: null }).profile, null);
});

test("validateNewUser : rejets", () => {
  for (const bad of [
    { ...ok, email: "pas-un-mail" },
    { ...ok, displayName: "  " },
    { ...ok, shortName: "J" },
    { ...ok, shortName: "JDUPO" },
    { ...ok, shortName: "J-D" },
    { ...ok, profile: "pilote" },
    { ...ok, category: "XX" },
    { ...ok, isAdmin: "oui" },
    null,
  ]) {
    assert.throws(() => validateNewUser(bad), ValidationError, JSON.stringify(bad));
  }
});

test("validateUserPatch : ne garde que les champs fournis, email interdit", () => {
  assert.deepEqual(validateUserPatch({ uid: "u1", category: "MIL", active: false }),
    { uid: "u1", patch: { category: "MIL", active: false } });
  assert.throws(() => validateUserPatch({ uid: "u1", email: "a@b.fr" }), ValidationError);
  assert.throws(() => validateUserPatch({ category: "GR" }), ValidationError);
  assert.throws(() => validateUserPatch({ uid: "u1" }), ValidationError);
});

test("validateAircraft : normalise, défauts, rejets", () => {
  assert.deepEqual(validateAircraft({ registration: " f-jabc ", label: " ULM 1 " }),
    { registration: "F-JABC", label: "ULM 1", active: true, amphibious: false });
  assert.equal(validateAircraft({ id: "a1", registration: "F-JABC", label: "x", active: false }).id, "a1");
  assert.throws(() => validateAircraft({ registration: "", label: "x" }), ValidationError);
  assert.throws(() => validateAircraft({ registration: "F-JABC", label: "" }), ValidationError);
});

test("validateAircraft : immatriculation limitée aux lettres, chiffres et tirets", () => {
  assert.throws(() => validateAircraft({ registration: "F/JABC", label: "x" }), ValidationError);
  assert.throws(() => validateAircraft({ registration: "F JABC", label: "x" }), ValidationError);
});

test("validateAircraft : amphibie", () => {
  assert.equal(validateAircraft({ registration: "F-JA", label: "x", amphibious: true }).amphibious, true);
});
