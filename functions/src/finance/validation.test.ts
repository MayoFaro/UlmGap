import { test } from "node:test";
import * as assert from "node:assert/strict";
import { ValidationError } from "../admin/validation";
import { validatePricing } from "./validation";

const ok = {
  flatFee: { GAP: 12_000, GR: 30_000, MIL: 50_000, EXT: 70_000 },
  includedMinutes: 75,
  minPlannedMinutes: 45,
  overtimeHourly: { GAP: 12_000, GR: 30_000, MIL: 30_000, EXT: 30_000 },
  fuelHourlyRate: 12_000,
};

test("validatePricing : cas nominal", () => {
  assert.deepEqual(validatePricing(ok), ok);
});

test("validatePricing : champ manquant", () => {
  for (const bad of [
    { ...ok, flatFee: undefined },
    { ...ok, includedMinutes: undefined },
    { ...ok, minPlannedMinutes: undefined },
    { ...ok, overtimeHourly: undefined },
    { ...ok, fuelHourlyRate: undefined },
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
  assert.doesNotThrow(() => validatePricing({ ...ok, includedMinutes: 600, minPlannedMinutes: 600 }));
});

test("validatePricing : message d'erreur au format attendu", () => {
  assert.throws(
    () => validatePricing({ ...ok, includedMinutes: 0 }),
    (e: unknown) => e instanceof ValidationError && e.message === "Tarifs invalides : includedMinutes.",
  );
});
