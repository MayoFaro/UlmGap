import * as admin from "firebase-admin";
import { setGlobalOptions } from "firebase-functions/v2";

if (admin.apps.length === 0) admin.initializeApp();

// Même région côté client (FirebaseFunctions.instanceFor(region: 'europe-west1')).
setGlobalOptions({ region: "europe-west1" });

export { adminCreateUser, adminUpdateUser } from "./admin/users";
export { adminUpsertAircraft } from "./admin/aircraft";
