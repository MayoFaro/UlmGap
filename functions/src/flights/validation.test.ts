import { test } from "node:test";
import * as assert from "node:assert/strict";
import { ValidationError } from "../admin/validation";
import { MAX_MANUAL_AMOUNT, formatFcfa } from "../rules/pricing";
import {
  MAX_ADVANCE_DAYS, checkDuration, checkHorizon, checkMinDuration, validateAdminUpdate, validateClosing,
  validateFlightId, validateFlightInput, validateRefusal, validateReviewChanges,
} from "./validation";

const T0 = 1_900_000_000_000;
const MIN = 60_000;
const ok = {
  start: T0, end: T0 + 60 * MIN, destination: " Lomé ", aircraftId: "a1",
  crew: ["u1", "u2"],
};

test("validateFlightInput : normalise, passagers par défaut vides", () => {
  assert.deepEqual(validateFlightInput(ok), {
    start: T0, end: T0 + 60 * MIN, destination: "Lomé", aircraftId: "a1",
    crew: ["u1", "u2"], passengers: [],
  });
  assert.equal(validateFlightInput({ ...ok, crew: ["u1"], passengers: [" Paul "], pricingMode: "fuel_only" })
    .passengers[0], "Paul");
});

test("validateFlightInput : la durée prévue minimale n'est plus vérifiée ici (déplacée dans planFlight)", () => {
  assert.equal(validateFlightInput({ ...ok, end: T0 + 30 * MIN }).end, T0 + 30 * MIN);
});

test("validateFlightInput : rejets", () => {
  for (const bad of [
    { ...ok, end: T0 - MIN },
    { ...ok, start: "demain" },
    { ...ok, destination: "  " },
    { ...ok, aircraftId: "" },
    { ...ok, crew: [] },
    { ...ok, crew: ["u1", "u1"] },
    { ...ok, crew: ["u1", ""] },
    { ...ok, passengers: ["Paul"] },
    { ...ok, crew: ["u1"], passengers: ["Paul", "Jacques"] },
    { ...ok, crew: ["u1"], passengers: [" "] },
    { ...ok, pricingMode: "custom" },
    null,
  ]) {
    assert.throws(() => validateFlightInput(bad), ValidationError, JSON.stringify(bad));
  }
});

test("validateFlightInput : durée prévue maximale 12 h", () => {
  assert.equal(validateFlightInput({ ...ok, end: T0 + 12 * 60 * MIN }).end, T0 + 12 * 60 * MIN);
  assert.throws(() => validateFlightInput({ ...ok, end: T0 + 12 * 60 * MIN + MIN }), ValidationError);
});

test("checkDuration : accepte 30 min, rejette fin ≤ départ et plus de 12 h", () => {
  assert.doesNotThrow(() => checkDuration(T0, T0 + 30 * MIN));
  assert.throws(
    () => checkDuration(T0, T0),
    (e: unknown) => e instanceof ValidationError && e.message === "L'heure de fin doit suivre le départ.",
  );
  assert.throws(
    () => checkDuration(T0, T0 - MIN),
    (e: unknown) => e instanceof ValidationError && e.message === "L'heure de fin doit suivre le départ.",
  );
  assert.throws(() => checkDuration(T0, T0 + 12 * 60 * MIN + MIN), ValidationError);
});

test("checkMinDuration : refuse 44 min avec un minimum de 45", () => {
  assert.throws(
    () => checkMinDuration(T0, T0 + 44 * MIN, 45),
    (e: unknown) => e instanceof ValidationError && e.message === "Durée prévue minimale : 45 min.",
  );
  assert.doesNotThrow(() => checkMinDuration(T0, T0 + 45 * MIN, 45));
});

test("checkHorizon : 366 jours acceptés, au-delà rejeté", () => {
  const now = Date.now();
  const day = 24 * 60 * MIN;
  assert.doesNotThrow(() => checkHorizon(now + MAX_ADVANCE_DAYS * day, now));
  assert.throws(() => checkHorizon(now + (MAX_ADVANCE_DAYS + 1) * day + MIN, now), ValidationError);
});

test("identifiants avec « / » rejetés proprement", () => {
  assert.throws(() => validateFlightInput({ ...ok, crew: ["u1", "u2/evil"] }), ValidationError);
  assert.throws(() => validateFlightInput({ ...ok, aircraftId: "a1/evil" }), ValidationError);
  assert.throws(() => validateFlightId({ flightId: "f1/evil" }), ValidationError);
  assert.throws(
    () => validateReviewChanges({ flightId: "f1", changes: { aircraftId: "a1/evil" } }),
    ValidationError,
  );
});

test("validateFlightId", () => {
  assert.equal(validateFlightId({ flightId: " f1 " }), "f1");
  assert.throws(() => validateFlightId({}), ValidationError);
});

test("validateReviewChanges : changements facultatifs", () => {
  assert.deepEqual(validateReviewChanges({ flightId: "f1" }), { flightId: "f1", changes: {} });
  assert.deepEqual(
    validateReviewChanges({ flightId: "f1", changes: { destination: " Kara ", pricingMode: "fuel_only" } }),
    { flightId: "f1", changes: { destination: "Kara", pricingMode: "fuel_only" } });
  assert.throws(() => validateReviewChanges({ flightId: "f1", changes: { start: -1 } }), ValidationError);
});

test("validateRefusal : motif facultatif, vide → null", () => {
  assert.deepEqual(validateRefusal({ flightId: "f1" }), { flightId: "f1", reason: null });
  assert.deepEqual(validateRefusal({ flightId: "f1", reason: "  " }), { flightId: "f1", reason: null });
  assert.deepEqual(validateRefusal({ flightId: "f1", reason: " Météo " }), { flightId: "f1", reason: "Météo" });
  assert.throws(() => validateRefusal({ flightId: "f1", reason: "x".repeat(201) }), ValidationError);
});

test("validateClosing : durée réelle, 1 à 720 min, entier", () => {
  assert.equal(validateClosing({ flightId: "f1", landings: 1, actualMinutes: 1, ...F }).actualMinutes, 1);
  assert.equal(validateClosing({ flightId: "f1", landings: 1, actualMinutes: 720, ...F }).actualMinutes, 720);
  for (const bad of [0, 721, 1.5, "90"]) {
    assert.throws(
      () => validateClosing({ flightId: "f1", landings: 1, actualMinutes: bad, ...F }),
      (e: unknown) => e instanceof ValidationError && e.message === "Durée réelle invalide (1 à 720 min).",
      JSON.stringify(bad),
    );
  }
});

test("validateClosing : flightId manquant → ValidationError", () => {
  assert.throws(() => validateClosing({ actualMinutes: 90 }), ValidationError);
});

test("validateClosing : montants absents ou null → null", () => {
  const r1 = validateClosing({ ...C, landings: 1, ...F });
  assert.equal(r1.shortFlightAmount, null);
  assert.equal(r1.customAmount, null);
  const r2 = validateClosing({ ...C, landings: 1, shortFlightAmount: null, customAmount: null, ...F });
  assert.equal(r2.shortFlightAmount, null);
  assert.equal(r2.customAmount, null);
});

test("validateClosing : montants entiers de 0 à 200 000 acceptés", () => {
  assert.equal(
    validateClosing({ ...C, landings: 1, shortFlightAmount: 0, ...F }).shortFlightAmount, 0);
  assert.equal(
    validateClosing({ ...C, landings: 1, shortFlightAmount: MAX_MANUAL_AMOUNT, ...F })
      .shortFlightAmount, MAX_MANUAL_AMOUNT);
  assert.equal(
    validateClosing({ ...C, landings: 1, customAmount: MAX_MANUAL_AMOUNT, ...F }).customAmount,
    MAX_MANUAL_AMOUNT);
});

test("validateClosing : montant négatif ou non entier → invalide (message générique)", () => {
  for (const bad of [-1, 1.5]) {
    assert.throws(
      () => validateClosing({ ...C, landings: 1, shortFlightAmount: bad, ...F }),
      (e: unknown) => e instanceof ValidationError && e.message === "Montant à facturer invalide.",
      JSON.stringify(bad),
    );
    assert.throws(
      () => validateClosing({ ...C, landings: 1, customAmount: bad, ...F }),
      (e: unknown) => e instanceof ValidationError && e.message === "Montant différent invalide.",
      JSON.stringify(bad),
    );
  }
});

test("validateClosing : montant au-delà de 200 000 → message exact avec espace insécable", () => {
  const expected = `Montant trop élevé (${formatFcfa(MAX_MANUAL_AMOUNT)} au maximum).`;
  assert.equal(expected, "Montant trop élevé (200 000 FCFA au maximum).");
  assert.throws(
    () => validateClosing({ ...C, landings: 1, shortFlightAmount: MAX_MANUAL_AMOUNT + 1, ...F }),
    (e: unknown) => e instanceof ValidationError && e.message === expected,
  );
  assert.throws(
    () => validateClosing({ ...C, landings: 1, customAmount: MAX_MANUAL_AMOUNT + 1, ...F }),
    (e: unknown) => e instanceof ValidationError && e.message === expected,
  );
});

test("validateAdminUpdate : champs du vol, champs de clôture facultatifs (absents = inchangés)", () => {
  assert.deepEqual(validateAdminUpdate({ ...ok, flightId: " f1 " }), {
    flightId: "f1",
    input: {
      start: T0, end: T0 + 60 * MIN, destination: "Lomé", aircraftId: "a1",
      crew: ["u1", "u2"], passengers: [],
    },
  });
  assert.deepEqual(
    validateAdminUpdate({
      ...ok, flightId: "f1", pricingMode: "fuel_only", actualMinutes: 30, shortFlightAmount: null,
    }),
    {
      flightId: "f1",
      input: {
        start: T0, end: T0 + 60 * MIN, destination: "Lomé", aircraftId: "a1",
        crew: ["u1", "u2"], passengers: [],
      },
      pricingMode: "fuel_only", actualMinutes: 30, shortFlightAmount: null,
    },
  );
});

test("validateAdminUpdate : mode custom avec montant différent ; mode choisi incompatible avec un montant différent", () => {
  const r = validateAdminUpdate({
    ...ok, crew: ["u1"], passengers: ["Paul"], flightId: "f1", pricingMode: "custom", customAmount: 20_000,
  });
  assert.equal(r.pricingMode, "custom");
  assert.equal(r.customAmount, 20_000);
  assert.equal(r.input.pricingMode, undefined);
  assert.throws(
    () => validateAdminUpdate({ ...ok, flightId: "f1", pricingMode: "standard", customAmount: 20_000 }),
    ValidationError,
  );
  assert.throws(
    () => validateAdminUpdate({ ...ok, flightId: "f1", pricingMode: "custom", customAmount: null }),
    ValidationError,
  );
});

test("validateAdminUpdate : mêmes rejets que la saisie et la clôture", () => {
  assert.throws(() => validateAdminUpdate({ ...ok }), ValidationError);
  assert.throws(() => validateAdminUpdate({ ...ok, flightId: "f1", crew: [] }), ValidationError);
  assert.throws(() => validateAdminUpdate({ ...ok, flightId: "f1", pricingMode: "gratuit" }), ValidationError);
  assert.throws(() => validateAdminUpdate({ ...ok, flightId: "f1", actualMinutes: 0 }), ValidationError);
  assert.throws(() => validateAdminUpdate({ ...ok, flightId: "f1", actualMinutes: null }), ValidationError);
  assert.throws(
    () => validateAdminUpdate({ ...ok, flightId: "f1", shortFlightAmount: MAX_MANUAL_AMOUNT + 1 }),
    ValidationError,
  );
  assert.throws(() => validateAdminUpdate({ ...ok, flightId: "f1", customAmount: -1 }), ValidationError);
});

const C = { flightId: "f1", actualMinutes: 60 };
const F = { fuelStart: 40, fuelAdded: 0, fuelEnd: 30 };
const isErr = (msg: string) => (e: unknown) => e instanceof ValidationError && e.message === msg;

test("validateClosing : atterrissages obligatoires, amerrissages 0 par défaut", () => {
  const r = validateClosing({ ...C, landings: 2, ...F });
  assert.equal(r.landings, 2);
  assert.equal(r.waterLandings, 0);
  assert.throws(() => validateClosing({ ...C, ...F }), isErr("Nombre d'atterrissages invalide (0 à 99)."));
});

test("validateClosing : nombres entiers de 0 à 99", () => {
  for (const bad of [100, -1, 1.5, "2"]) {
    assert.throws(() => validateClosing({ ...C, landings: bad, ...F }),
      isErr("Nombre d'atterrissages invalide (0 à 99)."), JSON.stringify(bad));
  }
  assert.throws(() => validateClosing({ ...C, landings: 1, waterLandings: 100, ...F }),
    isErr("Nombre d'amerrissages invalide (0 à 99)."));
});

test("validateClosing : au moins un posé au total", () => {
  assert.throws(() => validateClosing({ ...C, landings: 0, waterLandings: 0, ...F }),
    isErr("Au moins un atterrissage ou amerrissage."));
  const r = validateClosing({ ...C, landings: 0, waterLandings: 1, ...F });
  assert.equal(r.waterLandings, 1);
});

test("validateAdminUpdate : nombres absents inchangés, hors plage refusés", () => {
  const r = validateAdminUpdate({ ...ok, flightId: "f1" });
  assert.equal(r.landings, undefined);
  assert.equal(r.waterLandings, undefined);
  const r2 = validateAdminUpdate({ ...ok, flightId: "f1", landings: 3, waterLandings: 0 });
  assert.equal(r2.landings, 3);
  assert.equal(r2.waterLandings, 0);
  assert.throws(() => validateAdminUpdate({ ...ok, flightId: "f1", landings: 100 }),
    isErr("Nombre d'atterrissages invalide (0 à 99)."));
});

const closing = { flightId: "f1", actualMinutes: 60, landings: 1,
  fuelStartExpected: 40, fuelStart: 40, fuelAdded: 0, fuelEnd: 30 };

test("validateClosing : carburant rendu tel quel, prévu null accepté", () => {
  const v = validateClosing(closing);
  assert.equal(v.fuelStartExpected, 40);
  assert.equal(v.fuelStart, 40);
  assert.equal(v.fuelAdded, 0);
  assert.equal(v.fuelEnd, 30);
  assert.equal(validateClosing({ ...closing, fuelStartExpected: null }).fuelStartExpected, null);
  assert.equal(validateClosing({ ...closing, fuelStartExpected: undefined }).fuelStartExpected, null);
});

test("validateClosing : carburant obligatoire, entier de 0 à 100", () => {
  const msg = (m: string) => (e: unknown) => e instanceof ValidationError && e.message === m;
  assert.throws(() => validateClosing({ ...closing, fuelStart: undefined }),
    msg("Carburant au départ invalide (0 à 100 L)."));
  assert.throws(() => validateClosing({ ...closing, fuelAdded: -1 }),
    msg("Carburant ajouté invalide (0 à 100 L)."));
  assert.throws(() => validateClosing({ ...closing, fuelEnd: 101 }),
    msg("Carburant rangé invalide (0 à 100 L)."));
  assert.throws(() => validateClosing({ ...closing, fuelEnd: 12.5 }),
    msg("Carburant rangé invalide (0 à 100 L)."));
  assert.throws(() => validateClosing({ ...closing, fuelStartExpected: "40" }),
    msg("Carburant prévu invalide (0 à 100 L)."));
  assert.equal(validateClosing({ ...closing, fuelAdded: 100 }).fuelAdded, 100);
});

test("validateAdminUpdate : carburant facultatif, mêmes bornes", () => {
  const base = { flightId: "f1", ...ok };
  const none = validateAdminUpdate(base);
  assert.equal(none.fuelStart, undefined);
  assert.equal(none.fuelEnd, undefined);
  const v = validateAdminUpdate({ ...base, fuelStart: 10, fuelAdded: 20, fuelEnd: 5 });
  assert.deepEqual([v.fuelStart, v.fuelAdded, v.fuelEnd], [10, 20, 5]);
  assert.throws(() => validateAdminUpdate({ ...base, fuelEnd: 150 }), ValidationError);
});
