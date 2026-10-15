import { test } from "node:test";
import * as assert from "node:assert/strict";
import { ValidationError } from "../admin/validation";
import { cashDay, validateAddCashMovement, validateCashCorrection } from "./cash-validation";

const NOW = Date.UTC(2026, 9, 14, 12);

test("cashDay : défaut aujourd'hui, jour passé accepté, futur refusé", () => {
  assert.equal(cashDay(undefined, NOW), "2026-10-14");
  assert.equal(cashDay(null, NOW), "2026-10-14");
  assert.equal(cashDay("2026-10-01", NOW), "2026-10-01");
  assert.throws(() => cashDay("2026-10-15", NOW), ValidationError);
  assert.throws(() => cashDay(20261014, NOW), ValidationError);
});

test("validateAddCashMovement : achat carburant, note facultative, montant débité", () => {
  assert.deepEqual(
    validateAddCashMovement({ kind: "fuel_purchase", amount: 220_000, liters: 370 }, NOW),
    { kind: "fuel_purchase", amount: -220_000, date: "2026-10-14", note: null, liters: 370 },
  );
});

test("validateAddCashMovement : achat sans litres ni « Hors cuve » refusé", () => {
  for (const extra of [{}, { liters: null }, { outsideTank: false }]) {
    assert.throws(() => validateAddCashMovement({ kind: "fuel_purchase", amount: 220_000, ...extra }, NOW),
      (e) => e instanceof ValidationError &&
        e.message === "Litres obligatoires pour un achat de carburant (ou cochez « Hors cuve »).");
  }
});

test("validateAddCashMovement : achat hors cuve sans litres accepté, avec litres refusé", () => {
  assert.deepEqual(
    validateAddCashMovement({ kind: "fuel_purchase", amount: 220_000, outsideTank: true }, NOW),
    { kind: "fuel_purchase", amount: -220_000, date: "2026-10-14", note: null, liters: null },
  );
  assert.equal(
    validateAddCashMovement({ kind: "fuel_purchase", amount: 1_000, outsideTank: true, liters: null }, NOW).liters, null);
  assert.throws(() => validateAddCashMovement({ kind: "fuel_purchase", amount: 1_000, outsideTank: true, liters: 5 }, NOW),
    (e) => e instanceof ValidationError && e.message === "Litres inutiles pour un achat hors cuve.");
});

test("validateAddCashMovement : « Hors cuve » réservé à l'achat de carburant", () => {
  assert.throws(() => validateAddCashMovement({ kind: "maintenance", amount: 10_000, note: "x", outsideTank: true }, NOW),
    (e) => e instanceof ValidationError && e.message === "Hors cuve réservé à un achat de carburant.");
});

test("validateAddCashMovement : maintenance et recette exigent un objet", () => {
  assert.throws(() => validateAddCashMovement({ kind: "maintenance", amount: 10_000 }, NOW),
    (e) => e instanceof ValidationError && e.message === "Objet obligatoire.");
  assert.throws(() => validateAddCashMovement({ kind: "off_app_income", amount: 70_000, note: "  " }, NOW),
    (e) => e instanceof ValidationError && e.message === "Objet obligatoire.");
  assert.deepEqual(
    validateAddCashMovement({ kind: "maintenance", amount: 10_000, note: " Nettoyage ", date: "2026-10-09" }, NOW),
    { kind: "maintenance", amount: -10_000, date: "2026-10-09", note: "Nettoyage", liters: null },
  );
});

test("validateAddCashMovement : écart de caisse signé, motif obligatoire", () => {
  assert.throws(() => validateAddCashMovement({ kind: "cash_gap", amount: -5_000 }, NOW),
    (e) => e instanceof ValidationError && e.message === "Motif obligatoire pour un écart de caisse.");
  assert.deepEqual(
    validateAddCashMovement({ kind: "cash_gap", amount: -5_000, note: "Comptage", liters: null }, NOW),
    { kind: "cash_gap", amount: -5_000, date: "2026-10-14", note: "Comptage", liters: null },
  );
});

test("validateAddCashMovement : Crédit carburant et Fond initial refusés ici ; type inconnu", () => {
  for (const kind of ["fuel_credit", "opening", "autre", undefined]) {
    assert.throws(() => validateAddCashMovement({ kind, amount: 1_000, note: "x" }, NOW),
      (e) => e instanceof ValidationError && e.message === "Type d'opération invalide.", String(kind));
  }
});

test("validateAddCashMovement : montant nul, négatif hors écart, chaîne, note trop longue", () => {
  for (const bad of [
    { kind: "fuel_purchase", amount: 0 },
    { kind: "fuel_purchase", amount: -1 },
    { kind: "fuel_purchase", amount: "1000" },
    { kind: "fuel_purchase", amount: 1_000, note: "x".repeat(201) },
  ]) {
    assert.throws(() => validateAddCashMovement(bad, NOW), ValidationError, JSON.stringify(bad));
  }
});

test("validateCashCorrection : identifiant, montant entier (zéro accepté), note facultative", () => {
  assert.deepEqual(validateCashCorrection({ movementId: "m1", amount: 0 }),
    { movementId: "m1", amount: 0, note: null });
  assert.deepEqual(validateCashCorrection({ movementId: "m1", amount: 25_000, note: " Faute de frappe " }),
    { movementId: "m1", amount: 25_000, note: "Faute de frappe" });
  for (const bad of [{ amount: 1 }, { movementId: "a/b", amount: 1 }, { movementId: "m1", amount: 1.5 }]) {
    assert.throws(() => validateCashCorrection(bad), ValidationError, JSON.stringify(bad));
  }
});

test("validateAddCashMovement : litres entiers, réservés à l'achat de carburant", () => {
  const r = validateAddCashMovement({ kind: "fuel_purchase", amount: 220_000, liters: 200 }, NOW);
  assert.equal(r.liters, 200);
  assert.throws(() => validateAddCashMovement({ kind: "maintenance", amount: 10_000, note: "x", liters: 5 }, NOW),
    (e) => e instanceof ValidationError && e.message === "Litres réservés à un achat de carburant.");
  for (const liters of [0, 100_001, 1.5, "20", -3]) {
    assert.throws(() => validateAddCashMovement({ kind: "fuel_purchase", amount: 1_000, liters }, NOW),
      ValidationError, String(liters));
  }
  assert.equal(validateAddCashMovement({ kind: "fuel_purchase", amount: 1_000, liters: 100_000 }, NOW).liters, 100_000);
});
