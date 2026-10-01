import { test } from "node:test";
import * as assert from "node:assert/strict";
import { formatFcfa } from "./pricing";
import {
  cancelledPush, clubWhen, flightLine, FlightInfo, movementPush, refusedPush, reminderDue,
  reminderPush, requestPush, validatedPush,
} from "./notifications";

const utc = (iso: string) => Date.parse(iso);
const H = 3_600_000;
// Lundi 12 octobre 2026, 09:00–10:00 à Libreville (08:00–09:00 UTC).
const f: FlightInfo = {
  start: utc("2026-10-12T08:00:00Z"), end: utc("2026-10-12T09:00:00Z"),
  aircraft: "F-JABC", destination: "Lomé", crew: ["ldx", "dps"], passengers: [],
  createdBy: "ldx", instructorUid: "dps",
};
const names = { ldx: "LDX", dps: "DPS", ins: "INS" };
const line = "LDX/DPS, lundi 12 octobre, 09:00–10:00, F-JABC → Lomé";

test("clubWhen et flightLine : heure du club, passagers sans compte compris", () => {
  assert.equal(clubWhen(f.start, f.end), "lundi 12 octobre, 09:00–10:00");
  assert.equal(flightLine(f, names), line);
  assert.equal(flightLine({ ...f, crew: ["ldx"], passengers: ["Paul"] }, names),
    "LDX/Paul, lundi 12 octobre, 09:00–10:00, F-JABC → Lomé");
  assert.equal(flightLine({ ...f, crew: ["zzz"] }, names).startsWith("?,"), true);
});

test("demande : à l'instructeur désigné ; modifiée ; sans instructeur → null", () => {
  assert.deepEqual(requestPush(f, names, "ldx", false),
    { to: ["dps"], message: { title: "Nouvelle demande de vol", body: line } });
  assert.equal(requestPush(f, names, "ldx", true)!.message.title, "Demande de vol modifiée");
  assert.equal(requestPush({ ...f, instructorUid: null }, names, "ldx", false), null);
});

test("validée : créateur et équipage, jamais l'auteur, sans doublon", () => {
  assert.deepEqual(validatedPush(f, names, "dps", false),
    { to: ["ldx"], message: { title: "Vol validé", body: line } });
  const admin = validatedPush(f, names, "adm", true);
  assert.deepEqual(admin.to, ["ldx", "dps"]);
  assert.equal(admin.message.title, "Vol validé avec modifications");
});

test("refusée : au créateur, avec ou sans motif", () => {
  assert.deepEqual(refusedPush(f, names, "dps", "Météo"),
    { to: ["ldx"], message: { title: "Demande refusée", body: `${line}. Motif : Météo` } });
  assert.equal(refusedPush(f, names, "dps", null).message.body, line);
});

test("annulée : équipage et instructeur désigné, sauf l'auteur", () => {
  assert.deepEqual(cancelledPush({ ...f, crew: ["ldx"], instructorUid: "ins" }, names, "ldx"),
    { to: ["ins"], message: { title: "Vol annulé", body: "LDX, lundi 12 octobre, 09:00–10:00, F-JABC → Lomé" } });
  assert.deepEqual(cancelledPush(f, names, "adm").to, ["ldx", "dps"]);
});

test("rappel : à l'équipage", () => {
  assert.deepEqual(reminderPush(f, names), {
    to: ["ldx", "dps"],
    message: { title: "Vol à clôturer", body: `${line}. Pensez à le clôturer dans le carnet de vol.` },
  });
});

test("mouvement : intéressé et instructeurs, sauf l'auteur ; montants signés", () => {
  const p = movementPush({
    userUid: "ldx", shortName: "LDX", amount: 50_000, balanceAfter: 120_000, type: "credit",
    actor: "dps", instructors: ["dps", "ins"],
  });
  assert.deepEqual(p, {
    to: ["ldx", "ins"],
    message: {
      title: "Compte de LDX",
      body: `Crédit : +${formatFcfa(50_000)}. Nouveau solde : ${formatFcfa(120_000)}.`,
    },
  });
  const own = movementPush({
    userUid: "dps", shortName: "DPS", amount: -10_000, balanceAfter: 5_000, type: "correction",
    actor: "dps", instructors: ["dps", "ins"],
  });
  assert.deepEqual(own.to, ["ins"]);
  assert.equal(own.message.body, `Correction : ${formatFcfa(-10_000)}. Nouveau solde : ${formatFcfa(5_000)}.`);
  assert.equal(movementPush({
    userUid: "ldx", shortName: "LDX", amount: 3_000, balanceAfter: 0, type: "flight_adjustment",
    actor: "adm", instructors: [],
  }).message.body.startsWith("Régularisation : +"), true);
});

test("reminderDue : 24 h après la fin, puis toutes les 48 h", () => {
  const end = utc("2026-10-12T09:00:00Z");
  assert.equal(reminderDue(end, null, end + 24 * H - 60_000), false);
  assert.equal(reminderDue(end, null, end + 24 * H), true);
  const last = end + 25 * H;
  assert.equal(reminderDue(end, last, last + 47 * H), false);
  assert.equal(reminderDue(end, last, last + 48 * H), true);
});
