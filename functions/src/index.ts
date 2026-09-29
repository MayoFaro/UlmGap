import * as admin from "firebase-admin";
import { setGlobalOptions } from "firebase-functions/v2";

if (admin.apps.length === 0) admin.initializeApp();

// Même région côté client (FirebaseFunctions.instanceFor(region: 'europe-west1')).
setGlobalOptions({ region: "europe-west1" });

export { adminCreateUser, adminUpdateUser } from "./admin/users";
export { adminUpsertAircraft } from "./admin/aircraft";
export { adminUpdatePricing } from "./finance/pricing-store";
export { createFlightFn as createFlight, updateFlightFn as updateFlight } from "./flights/edit";
export {
  validateFlightFn as validateFlight,
  refuseFlightFn as refuseFlight,
  cancelFlightFn as cancelFlight,
} from "./flights/actions";
