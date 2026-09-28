// DEV/RECETTE UNIQUEMENT. Crée (ou remet à niveau) les 8 comptes de test
// fixes, e-mail déjà vérifié, avec le mot de passe donné. Usage :
//   node scripts/seed-test-users.js --project ulmgap-dev --password <mot de passe, 8 car. min>
// Identifiants : gcloud auth application-default login (compte propriétaire du projet).
const admin = require("firebase-admin");

const arg = (k) => {
  const i = process.argv.indexOf(`--${k}`);
  return i > 0 ? process.argv[i + 1] : undefined;
};
const projectId = arg("project");
const password = arg("password") || "";
if (!projectId || password.length < 8) {
  console.error("Usage : --project <id> --password <mot de passe, 8 car. min>");
  process.exit(1);
}

// Module compilé : lancer `npm run build` avant ce script.
const { assertSeedAllowed, seedTestUsers } = require("../lib/admin/seed");
assertSeedAllowed(projectId); // avant toute connexion Firebase : jamais sur un vrai projet.

admin.initializeApp({ projectId });
(async () => {
  const emails = await seedTestUsers(admin.auth(), admin.firestore(), password);
  console.log(`Comptes de test prêts (${emails.length}) :`);
  emails.forEach((e) => console.log(`  - ${e}`));
})().catch((e) => { console.error(e.message); process.exit(1); });
