// Import unique de l'historique de caisse (spec §11.7) : CSV normalisé
// « date;kind;amount;note », montants signés. Aucun compte d'adhérent n'est
// touché. Utilisé par scripts/import-cashbox.js.
import * as admin from "firebase-admin";
import { cashboxRef } from "../finance/cash-ledger";
import { CASH_KINDS, CashKind, cashSign, isValidCashDay } from "../rules/cash";

type Db = FirebaseFirestore.Firestore;
export interface CashImportRow { date: string; kind: CashKind; amount: number; note: string }

const HEADER = "date;kind;amount;note";

export function parseCashCsv(text: string, nowMs = Date.now()): CashImportRow[] {
  const lines = text.replace(/^﻿/, "").split(/\r?\n/);
  if (lines[0]?.trim() !== HEADER) throw new Error(`En-tête attendu : ${HEADER}`);
  const rows: CashImportRow[] = [];
  lines.forEach((line, i) => {
    if (i === 0 || line.trim() === "") return;
    const n = i + 1;
    const [date = "", kind = "", amount = "", ...rest] = line.split(";");
    const note = rest.join(";").trim();
    if (!isValidCashDay(date.trim(), nowMs)) throw new Error(`Ligne ${n} : date invalide.`);
    if (!CASH_KINDS.includes(kind.trim() as CashKind)) throw new Error(`Ligne ${n} : type inconnu (${kind.trim()}).`);
    const k = kind.trim() as CashKind;
    const value = Number(amount.trim());
    if (!/^-?\d+$/.test(amount.trim()) || value === 0) throw new Error(`Ligne ${n} : montant invalide.`);
    const sign = cashSign(k);
    if (sign !== 0 && Math.sign(value) !== sign) throw new Error(`Ligne ${n} : signe incohérent avec ${k}.`);
    if (!note) throw new Error(`Ligne ${n} : libellé d'origine manquant.`);
    rows.push({ date: date.trim(), kind: k, amount: value, note });
  });
  return rows;
}

export async function importCashbox(db: Db, rows: CashImportRow[]): Promise<{ count: number; balance: number }> {
  if (rows.length === 0 || rows.length > 400) throw new Error("Entre 1 et 400 lignes.");
  const existing = await db.collection("cashMovements").limit(1).get();
  if (!existing.empty) throw new Error("La caisse contient déjà des opérations : import refusé.");
  // Tri stable par date : l'ordre du fichier départage un même jour.
  const sorted = rows.map((r, i) => ({ r, i }))
    .sort((a, b) => a.r.date.localeCompare(b.r.date) || a.i - b.i)
    .map((x) => x.r);
  const batch = db.batch();
  const base = Date.now();
  let balance = 0;
  sorted.forEach((r, i) => {
    balance += r.amount;
    batch.create(db.collection("cashMovements").doc(), {
      kind: r.kind, amount: r.amount, date: r.date, userUid: null, transactionId: null,
      note: r.note, correctsId: null, imported: true, by: "import",
      // Ordre de saisie strictement croissant (tri date puis `at` dans l'app).
      at: admin.firestore.Timestamp.fromMillis(base + i),
      balanceAfter: balance,
    });
  });
  batch.set(cashboxRef(db), {
    balance, migrationClosedAt: null, updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return { count: sorted.length, balance };
}
