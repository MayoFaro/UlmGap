import { test } from "node:test";
import * as assert from "node:assert/strict";
import { ValidationError } from "../admin/validation";
import {
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

test("validateFlightInput : 45 min pile acceptées", () => {
  assert.equal(validateFlightInput({ ...ok, end: T0 + 45 * MIN }).end, T0 + 45 * MIN);
});

test("validateFlightInput : rejets", () => {
  for (const bad of [
    { ...ok, end: T0 + 44 * MIN },
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
