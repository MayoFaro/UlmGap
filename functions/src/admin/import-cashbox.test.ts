import { test } from "node:test";
import * as assert from "node:assert/strict";
import { parseCashCsv } from "./import-cashbox";

const NOW = Date.UTC(2026, 9, 14, 12);
const HEAD = "date;kind;amount;note";

test("parseCashCsv : lignes signées, BOM, CRLF, lignes vides, point-virgule dans la note", () => {
  const rows = parseCashCsv(`﻿${HEAD}\r\n2025-03-05;opening;10000000;Fond initial\r\n\r\n` +
    "2026-10-12;fuel_purchase;-220000;ESSENCE\n2026-10-06;fuel_credit;20000;acompte LCM; espèces\n", NOW);
  assert.deepEqual(rows, [
    { date: "2025-03-05", kind: "opening", amount: 10_000_000, note: "Fond initial" },
    { date: "2026-10-12", kind: "fuel_purchase", amount: -220_000, note: "ESSENCE" },
    { date: "2026-10-06", kind: "fuel_credit", amount: 20_000, note: "acompte LCM; espèces" },
  ]);
});

test("parseCashCsv : erreurs avec numéro de ligne", () => {
  const bad: [string, string][] = [
    ["x;y;z;w\n", "En-tête attendu : date;kind;amount;note"],
    [`${HEAD}\n2026-13-01;maintenance;-1;x\n`, "Ligne 2 : date invalide."],
    [`${HEAD}\n2026-10-01;autre;-1;x\n`, "Ligne 2 : type inconnu (autre)."],
    [`${HEAD}\n2026-10-01;maintenance;12,5;x\n`, "Ligne 2 : montant invalide."],
    [`${HEAD}\n2026-10-01;maintenance;1000;x\n`, "Ligne 2 : signe incohérent avec maintenance."],
    [`${HEAD}\n2026-10-01;maintenance;-1000;\n`, "Ligne 2 : libellé d'origine manquant."],
  ];
  for (const [text, message] of bad) assert.throws(() => parseCashCsv(text, NOW), { message });
});
