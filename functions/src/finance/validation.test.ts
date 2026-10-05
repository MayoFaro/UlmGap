import { test } from "node:test";
import * as assert from "node:assert/strict";
import { ValidationError } from "../admin/validation";
import { validateCorrection, validateCredit, validatePricing } from "./validation";

const ok = {
  flatFee: { GAP: 12_000, GR: 30_000, MIL: 50_000, EXT: 70_000 },
  includedMinutes: 60,
  toleranceMinutes: 75,
  minPlannedMinutes: 45,
  overtimeHourly: { GAP: 12_000, GR: 30_000, MIL: 30_000, EXT: 30_000 },
  fuelHourlyRate: 12_000,
  instructionCredit: 20_000,
  baptismFees: { local: 70_000, nyonye: 90_000, awagne: 110_000 },
};

test("validatePricing : cas nominal", () => {
  assert.deepEqual(validatePricing(ok), ok);
});

test("validatePricing : champ manquant", () => {
  for (const bad of [
    { ...ok, flatFee: undefined },
    { ...ok, includedMinutes: undefined },
    { ...ok, toleranceMinutes: undefined },
    { ...ok, toleranceMinutes: 601 },
    { ...ok, toleranceMinutes: 0 },
    { ...ok, minPlannedMinutes: undefined },
    { ...ok, overtimeHourly: undefined },
    { ...ok, fuelHourlyRate: undefined },
    { ...ok, instructionCredit: undefined },
    { ...ok, baptismFees: undefined },
    { ...ok, baptismFees: { local: 70_000, nyonye: 90_000 } }, // awagne manquant
    { ...ok, instructionCredit: -1 },
    { ...ok, baptismFees: { ...ok.baptismFees, nyonye: -1 } },
    { ...ok, baptismFees: { ...ok.baptismFees, awagne: 1_000_001 } },
    { ...ok, flatFee: { GAP: 12_000, GR: 30_000, MIL: 50_000 } }, // EXT manquant
    null,
    {},
  ]) {
    assert.throws(() => validatePricing(bad), ValidationError, JSON.stringify(bad));
  }
});

test("validatePricing : valeur négative", () => {
  assert.throws(
    () => validatePricing({ ...ok, flatFee: { ...ok.flatFee, GAP: -1 } }),
    ValidationError,
  );
  assert.throws(
    () => validatePricing({ ...ok, includedMinutes: -1 }),
    ValidationError,
  );
});

test("validatePricing : valeur décimale", () => {
  assert.throws(
    () => validatePricing({ ...ok, fuelHourlyRate: 12_000.5 }),
    ValidationError,
  );
});

test("validatePricing : hors plage", () => {
  assert.throws(() => validatePricing({ ...ok, includedMinutes: 0 }), ValidationError);
  assert.throws(() => validatePricing({ ...ok, includedMinutes: 601 }), ValidationError);
  assert.throws(() => validatePricing({ ...ok, minPlannedMinutes: 0 }), ValidationError);
  assert.throws(() => validatePricing({ ...ok, minPlannedMinutes: 601 }), ValidationError);
  assert.throws(
    () => validatePricing({ ...ok, flatFee: { ...ok.flatFee, GAP: 1_000_001 } }),
    ValidationError,
  );
  assert.doesNotThrow(() => validatePricing({ ...ok, includedMinutes: 600, toleranceMinutes: 600, minPlannedMinutes: 600 }));
});

test("validatePricing : message d'erreur au format attendu", () => {
  assert.throws(
    () => validatePricing({ ...ok, includedMinutes: 0 }),
    (e: unknown) => e instanceof ValidationError && e.message === "Tarifs invalides : includedMinutes.",
  );
});

test("validateCredit : cas nominal, avec et sans motif", () => {
  assert.deepEqual(
    validateCredit({ userUid: "u1", amount: 50_000 }),
    { userUid: "u1", amount: 50_000, reason: null },
  );
  assert.deepEqual(
    validateCredit({ userUid: "u1", amount: 50_000, reason: " Versement caisse " }),
    { userUid: "u1", amount: 50_000, reason: "Versement caisse" },
  );
});

test("validateCredit : aucun plafond, 1 000 000 accepté", () => {
  assert.deepEqual(
    validateCredit({ userUid: "u1", amount: 1_000_000 }),
    { userUid: "u1", amount: 1_000_000, reason: null },
  );
});

test("validateCredit : montant invalide (zéro, négatif, décimal, manquant)", () => {
  for (const bad of [0, -1, 100.5, undefined, null, "100"]) {
    assert.throws(() => validateCredit({ userUid: "u1", amount: bad }), ValidationError, JSON.stringify(bad));
  }
});

test("validateCredit : compte manquant ou invalide", () => {
  for (const bad of [undefined, null, "", "a/b"]) {
    assert.throws(() => validateCredit({ userUid: bad, amount: 100 }), ValidationError, JSON.stringify(bad));
  }
});

test("validateCorrection : nouveau solde (positif, nul ou négatif) et motif", () => {
  for (const newBalance of [350_000, 0, -10_000, 10_000_000]) {
    assert.deepEqual(
      validateCorrection({ userUid: "u1", newBalance, reason: "Erreur de saisie" }),
      { userUid: "u1", newBalance, reason: "Erreur de saisie" },
    );
  }
});

test("validateCorrection : nouveau solde invalide (décimal, manquant, texte)", () => {
  for (const bad of [100.5, undefined, null, "100"]) {
    assert.throws(
      () => validateCorrection({ userUid: "u1", newBalance: bad, reason: "Motif" }),
      (e: unknown) => e instanceof ValidationError && e.message === "Nouveau solde invalide.",
      JSON.stringify(bad),
    );
  }
});

test("validateCorrection : motif obligatoire (absent, vide)", () => {
  for (const bad of [undefined, null, "", "   "]) {
    assert.throws(
      () => validateCorrection({ userUid: "u1", newBalance: 100, reason: bad }),
      (e: unknown) => e instanceof ValidationError && e.message === "Motif obligatoire pour une correction.",
      JSON.stringify(bad),
    );
  }
});

test("validateCorrection : motif de plus de 200 caractères → message distinct", () => {
  assert.throws(
    () => validateCorrection({ userUid: "u1", newBalance: 100, reason: "x".repeat(201) }),
    (e: unknown) => e instanceof ValidationError && e.message === "Motif trop long (200 caractères au maximum).",
  );
  assert.equal(validateCorrection({ userUid: "u1", newBalance: 100, reason: "x".repeat(200) }).reason.length, 200);
});

test("validatePricing : tolérance inférieure au temps couvert refusée", () => {
  assert.throws(
    () => validatePricing({ ...ok, includedMinutes: 80, toleranceMinutes: 75 }),
    (e: unknown) => e instanceof ValidationError && e.message === "La tolérance doit être au moins égale au temps couvert.",
  );
  assert.doesNotThrow(() => validatePricing({ ...ok, includedMinutes: 75, toleranceMinutes: 75 }));
});
