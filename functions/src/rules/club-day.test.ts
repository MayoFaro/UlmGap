import { test } from "node:test";
import * as assert from "node:assert/strict";
import { clubDay, isOnOrBeforeClubToday } from "./club-day";

const utc = (iso: string) => Date.parse(iso);

test("clubDay : minuit à Libreville = 23:00 UTC la veille", () => {
  assert.equal(clubDay(utc("2026-10-14T23:00:00Z")), clubDay(utc("2026-10-15T12:00:00Z")));
  assert.equal(clubDay(utc("2026-10-14T22:59:59Z")) + 1, clubDay(utc("2026-10-15T12:00:00Z")));
});

test("isOnOrBeforeClubToday : plus tard le même jour → oui", () => {
  assert.equal(isOnOrBeforeClubToday(utc("2026-10-15T21:30:00Z"), utc("2026-10-15T07:00:00Z")), true);
});

test("isOnOrBeforeClubToday : jour passé → oui ; lendemain → non", () => {
  assert.equal(isOnOrBeforeClubToday(utc("2026-10-10T09:00:00Z"), utc("2026-10-15T07:00:00Z")), true);
  assert.equal(isOnOrBeforeClubToday(utc("2026-10-16T08:00:00Z"), utc("2026-10-15T07:00:00Z")), false);
});

test("isOnOrBeforeClubToday : 23:30 UTC est déjà le lendemain au club", () => {
  // now = 15/10 22:00 UTC (23:00 au club) ; start = 15/10 23:30 UTC (16/10 00:30 au club).
  assert.equal(isOnOrBeforeClubToday(utc("2026-10-15T23:30:00Z"), utc("2026-10-15T22:00:00Z")), false);
});
