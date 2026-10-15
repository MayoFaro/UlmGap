// Cuve (spec §13.3) : plein d'un appareil hors vol, relevé de jauge.
import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Caller, requireStaff } from "../auth/guards";
import { asInvalid } from "../common/errors";
import { postTankMovement, readTank } from "./tank-ledger";
import { validateAircraftFill, validateGaugeReading } from "./tank-validation";

export interface TankResult { id: string; liters: number }

export async function addAircraftFill(caller: Caller | undefined, data: unknown): Promise<TankResult> {
  const db = admin.firestore();
  const me = await requireStaff(db, caller);
  const v = asInvalid(() => validateAircraftFill(data, Date.now()));
  const aircraftRef = db.collection("aircraft").doc(v.aircraftId);
  return db.runTransaction(async (tx) => {
    const aircraft = await tx.get(aircraftRef);
    if (!aircraft.exists) throw new HttpsError("not-found", "Appareil introuvable.");
    const tank = await readTank(tx, db);
    const r = postTankMovement(tx, db, {
      kind: "aircraft_fill", liters: -v.liters, date: v.date, flightId: null, aircraftId: v.aircraftId,
      cashMovementId: null, measuredLiters: null, technical: false, note: v.note,
      by: me.uid, currentLiters: tank.liters,
    });
    const before = (aircraft.get("fuelLiters") as number | undefined) ?? 0;
    tx.update(aircraftRef, {
      fuelLiters: Math.min(100, before + v.liters),
      fuelFlightId: null,
      fuelFlightStart: admin.firestore.Timestamp.now(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { id: r.id, liters: r.litersAfter };
  });
}

export async function addGaugeReading(caller: Caller | undefined, data: unknown): Promise<TankResult> {
  const db = admin.firestore();
  const me = await requireStaff(db, caller);
  const v = asInvalid(() => validateGaugeReading(data, Date.now()));
  return db.runTransaction(async (tx) => {
    const tank = await readTank(tx, db);
    const r = postTankMovement(tx, db, {
      kind: "gauge", liters: v.measuredLiters - tank.liters, date: v.date, flightId: null, aircraftId: null,
      cashMovementId: null, measuredLiters: v.measuredLiters, technical: false, note: v.note,
      by: me.uid, currentLiters: tank.liters,
    });
    return { id: r.id, liters: r.litersAfter };
  });
}

export const addAircraftFillFn = onCall((req) => addAircraftFill(req.auth as Caller | undefined, req.data));
export const addGaugeReadingFn = onCall((req) => addGaugeReading(req.auth as Caller | undefined, req.data));
