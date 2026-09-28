import * as admin from "firebase-admin";

type AuthLike = Pick<admin.auth.Auth, "getUserByEmail" | "createUser">;

/**
 * Crée ou promeut un admin. Seul « compte inexistant » déclenche la création
 * du compte Auth : toute autre erreur (Authentication non activé…) remonte.
 * Un document users existant n'est que promu : solde, catégorie et createdAt
 * sont conservés.
 */
export async function bootstrapAdmin(
  auth: AuthLike,
  db: FirebaseFirestore.Firestore,
  input: { email: string; name: string; short: string },
): Promise<string> {
  let uid: string;
  try {
    uid = (await auth.getUserByEmail(input.email)).uid;
  } catch (e) {
    if ((e as { code?: string }).code !== "auth/user-not-found") throw e;
    uid = (await auth.createUser({ email: input.email, displayName: input.name })).uid;
  }
  const users = db.collection("users").doc(uid);
  const profiles = db.collection("profiles").doc(uid);
  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.runTransaction(async (tx) => {
    const current = await tx.get(users);
    if (current.exists) {
      tx.update(users, { isAdmin: true, active: true, updatedAt: now });
      tx.set(profiles, { active: true }, { merge: true });
      return;
    }
    tx.set(users, {
      email: input.email, displayName: input.name, shortName: input.short,
      profile: null, category: "GAP", isAdmin: true, active: true, balance: 0,
      fcmToken: null, createdAt: now, updatedAt: now,
    });
    tx.set(profiles, {
      displayName: input.name, shortName: input.short, profile: null, active: true,
    });
  });
  return uid;
}
