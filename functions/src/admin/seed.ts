import * as admin from "firebase-admin";
import { Category, Profile } from "./validation";

type AuthLike = Pick<admin.auth.Auth, "getUserByEmail" | "createUser" | "updateUser">;

export interface TestAccount {
  code: string;
  name: string;
  short: string;
  profile: Profile | null;
  category: Category;
}

/**
 * Comptes de test fixes (un par profil/appartenance), pour la recette en
 * dev. E-mails en `test-<code>@ulmgap.invalid` (domaine réservé, jamais
 * livrable).
 */
export const TEST_ACCOUNTS: readonly TestAccount[] = [
  { code: "eleve-ext", name: "Élève Externe", short: "EEX", profile: "eleve", category: "EXT" },
  { code: "eleve-gap", name: "Élève GAP", short: "EGA", profile: "eleve", category: "GAP" },
  { code: "solo-gap", name: "Lâché Solo GAP", short: "LSG", profile: "lache_solo", category: "GAP" },
  {
    code: "ltm-gap", name: "Lâché Mission GAP", short: "LMG",
    profile: "lache_toute_mission", category: "GAP",
  },
  {
    code: "ltm-mil", name: "Lâché Mission MIL", short: "LMM",
    profile: "lache_toute_mission", category: "MIL",
  },
  { code: "instr-gap", name: "Instructeur GAP", short: "IGA", profile: "instructeur", category: "GAP" },
  { code: "instr-gr", name: "Instructeur GR", short: "IGR", profile: "instructeur", category: "GR" },
  { code: "gest-gap", name: "Gestionnaire GAP", short: "GES", profile: null, category: "GAP" },
] as const;

/**
 * Refuse tout projet qui n'est ni `ulmgap-dev` ni un projet d'émulateur
 * (`demo-*`) : ce script ne doit jamais pouvoir toucher un vrai projet
 * (prod y compris). À appeler avant toute initialisation Firebase.
 */
export function assertSeedAllowed(projectId: string): void {
  if (projectId !== "ulmgap-dev" && !projectId.startsWith("demo-")) {
    throw new Error(
      `Comptes de test refusés pour le projet « ${projectId} » : ` +
        "seuls ulmgap-dev et les projets demo-* sont autorisés.",
    );
  }
}

/**
 * Crée ou remet à niveau les comptes de test fixes (`TEST_ACCOUNTS`) :
 * e-mail vérifié, mot de passe donné, compte actif. Idempotente : une
 * relance ne duplique rien et ne touche ni `balance` ni `createdAt` d'un
 * compte déjà existant.
 */
export async function seedTestUsers(
  auth: AuthLike,
  db: FirebaseFirestore.Firestore,
  password: string,
): Promise<string[]> {
  const emails: string[] = [];
  for (const account of TEST_ACCOUNTS) {
    const email = `test-${account.code}@ulmgap.invalid`;
    emails.push(email);

    let uid: string;
    try {
      uid = (await auth.getUserByEmail(email)).uid;
      await auth.updateUser(uid, { password, emailVerified: true, disabled: false });
    } catch (e) {
      if ((e as { code?: string }).code !== "auth/user-not-found") throw e;
      uid = (await auth.createUser({
        email, password, displayName: account.name, emailVerified: true,
      })).uid;
    }

    const usersRef = db.collection("users").doc(uid);
    const profilesRef = db.collection("profiles").doc(uid);
    const now = admin.firestore.FieldValue.serverTimestamp();
    const base = {
      email, displayName: account.name, shortName: account.short,
      profile: account.profile, category: account.category,
      isAdmin: false, active: true, updatedAt: now,
    };
    await db.runTransaction(async (tx) => {
      const current = await tx.get(usersRef);
      // balance/createdAt/fcmToken : seulement à la création, jamais écrasés
      // ensuite (set(..., { merge: true }) ci-dessous ne les touche pas si
      // absents), comme pour createUser/bootstrapAdmin.
      const data = current.exists ? base : { ...base, balance: 0, fcmToken: null, createdAt: now };
      tx.set(usersRef, data, { merge: true });
      tx.set(profilesRef, {
        displayName: account.name, shortName: account.short,
        profile: account.profile, active: true,
      });
    });
  }
  return emails;
}
