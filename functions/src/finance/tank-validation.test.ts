import { test } from "node:test";
import * as assert from "node:assert/strict";
import { ValidationError } from "../admin/validation";
import { validateAircraftFill, validateGaugeReading } from "./tank-validation";

const NOW = Date.UTC(2026, 9, 14, 12);

test("validateAircraftFill : cas nominal, date par défaut, note", () => {
  assert.deepEqual(validateAircraftFill({ aircraftId: "a1", liters: 40 }, NOW),
    { aircraftId: "a1", liters: 40, date: "2026-10-14", note: null });
  assert.deepEqual(
    validateAircraftFill({ aircraftId: "a1", liters: 100, date: "2026-10-01", note: " Plein " }, NOW),
    { aircraftId: "a1", liters: 100, date: "2026-10-01", note: "Plein" });
});

test("validateAircraftFill : refus", () => {
  for (const bad of [
    { aircraftId: "a1", liters: 0 },
    { aircraftId: "a1", liters: 101 },
    { aircraftId: "a1", liters: 1.5 },
    { aircraftId: "a1", liters: "5" },
    { aircraftId: "", liters: 5 },
    { aircraftId: "a/b", liters: 5 },
    { liters: 5 },
    { aircraftId: "a1", liters: 5, date: "2026-10-15" },
    { aircraftId: "a1", liters: 5, note: "x".repeat(201) },
    null,
  ]) {
    assert.throws(() => validateAircraftFill(bad, NOW), ValidationError, JSON.stringify(bad));
  }
});

test("validateGaugeReading : 0 accepté, négatif et futur refusés", () => {
  assert.deepEqual(validateGaugeReading({ measuredLiters: 0 }, NOW),
    { measuredLiters: 0, date: "2026-10-14", note: null });
  assert.equal(validateGaugeReading({ measuredLiters: 100_000, note: "ok" }, NOW).note, "ok");
  for (const bad of [
    { measuredLiters: -1 }, { measuredLiters: 100_001 }, { measuredLiters: 2.5 },
    { measuredLiters: "3" }, {}, { measuredLiters: 5, date: "2026-10-15" },
    { measuredLiters: 5, note: "x".repeat(201) },
  ]) {
    assert.throws(() => validateGaugeReading(bad, NOW), ValidationError, JSON.stringify(bad));
  }
});
