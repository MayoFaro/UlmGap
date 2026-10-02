// DEV/RECETTE UNIQUEMENT. Crédite chaque compte de 500 000 FCFA (montant
// personnalisable), une seule fois par compte, par une transaction `credit`
// de motif « Crédit initial (tests) ». Usage :
//   node scripts/seed-dev-credit.js --project ulmgap-dev [--amount 500000]
// Identifiants : gcloud auth application-default login (compte propriétaire du projet).
const admin = require("firebase-admin");

const arg = (k) => {
  const i = process.argv.indexOf(`--${k}`);
  return i > 0 ? process.argv[i + 1] : undefined;
};
const projectId = arg("project");
const amount = Number(arg("amount") ?? "500000");
if (!projectId || !Number.isInteger(amount) || amount <= 0) {
  console.error("Usage : --project <id> [--amount <montant entier positif>]");
  process.exit(1);
}

// Module compilé : lancer `npm run build` avant ce script.
const { assertSeedAllowed } = require("../lib/admin/seed");
const { seedInitialCredit } = require("../lib/admin/seed-credit");
assertSeedAllowed(projectId); // avant toute connexion Firebase : jamais sur un vrai projet.

admin.initializeApp({ projectId });
(async () => {
  const { credited, skipped } = await seedInitialCredit(admin.firestore(), amount);
  console.log(`Comptes crédités de ${amount} FCFA (${credited.length}) :`);
  credited.forEach((uid) => console.log(`  - ${uid}`));
  console.log(`Comptes déjà crédités, ignorés (${skipped.length}).`);
})().catch((e) => { console.error(e.message); process.exit(1); });
