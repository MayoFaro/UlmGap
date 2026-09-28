import { HttpsError } from "firebase-functions/v2/https";
import { ValidationError } from "../admin/validation";

/** Exécute une validation pure ; ValidationError → HttpsError invalid-argument. */
export function asInvalid<T>(fn: () => T): T {
  try {
    return fn();
  } catch (e) {
    if (e instanceof ValidationError) throw new HttpsError("invalid-argument", e.message);
    throw e;
  }
}
