import { test } from "node:test";
import * as assert from "node:assert/strict";
import { ValidationError } from "../admin/validation";
import {
  CASH_KINDS, cashSign, clubDayString, formatCashDay, isValidCashDay, signedCashAmount,
} from "./cash";

test("cashSign : entrées, sorties, écart", () => {
  assert.equal(cashSign("fuel_credit"), 1);
  assert.equal(cashSign("off_app_income"), 1);
  assert.equal(cashSign("opening"), 1);
  assert.equal(cashSign("fuel_purchase"), -1);
  assert.equal(cashSign("maintenance"), -1);
  assert.equal(cashSign("cash_gap"), 0);
  assert.equal(CASH_KINDS.length, 6);
});

test("signedCashAmount : saisie positive, signe selon le type", () => {
  assert.equal(signedCashAmount("fuel_credit", 50_000, false), 50_000);
  assert.equal(signedCashAmount("fuel_purchase", 474_000, false), -474_000);
  assert.equal(signedCashAmount("maintenance", 10_000, false), -10_000);
  assert.equal(signedCashAmount("cash_gap", -3_000, false), -3_000);
  assert.equal(signedCashAmount("cash_gap", 3_000, false), 3_000);
});

test("signedCashAmount : zéro seulement pour une correction, jamais -0", () => {
  assert.throws(() => signedCashAmount("maintenance", 0, false), ValidationError);
  assert.throws(() => signedCashAmount("cash_gap", 0, false), ValidationError);
  assert.ok(Object.is(signedCashAmount("maintenance", 0, true), 0));
  assert.equal(signedCashAmount("cash_gap", 0, true), 0);
});

test("signedCashAmount : négatif hors écart, décimal, non-nombre refusés", () => {
  assert.throws(() => signedCashAmount("fuel_purchase", -10, false), ValidationError);
  assert.throws(() => signedCashAmount("fuel_credit", 10.5, false), ValidationError);
  assert.throws(() => signedCashAmount("fuel_credit", Number.NaN, false), ValidationError);
});

test("clubDayString : jour à l'heure du club (UTC+1)", () => {
  assert.equal(clubDayString(Date.UTC(2026, 9, 14, 22, 59)), "2026-10-14");
  assert.equal(clubDayString(Date.UTC(2026, 9, 14, 23, 30)), "2026-10-15");
});

test("isValidCashDay : format, date réelle, pas de futur", () => {
  const now = Date.UTC(2026, 9, 14, 12);
  assert.equal(isValidCashDay("2026-10-14", now), true);
  assert.equal(isValidCashDay("2025-03-05", now), true);
  assert.equal(isValidCashDay("2026-10-15", now), false); // demain
  assert.equal(isValidCashDay("2026-02-30", now), false);
  assert.equal(isValidCashDay("14/10/2026", now), false);
  assert.equal(isValidCashDay("1999-12-31", now), false); // avant 2000
});

test("formatCashDay : JJ/MM/AAAA", () => {
  assert.equal(formatCashDay("2026-10-12"), "12/10/2026");
});
