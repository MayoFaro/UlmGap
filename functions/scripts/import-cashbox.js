// Import unique de l'historique de caisse (spec §11.7). Usage :
//   node scripts/import-cashbox.js --project ulmgap-dev --file ../docs/caisse-import.csv [--dry-run]
// --dry-run : analyse le fichier et affiche le total, sans rien écrire.
// Identifiants : gcloud auth application-default login (compte propriétaire du projet).
const fs = require("fs");
const admin = require("firebase-admin");

const arg = (k) => {
  const i = process.argv.indexOf(`--${k}`);
  return i > 0 ? process.argv[i + 1] : undefined;
};
const projectId = arg("project");
const file = arg("file");
const dryRun = process.argv.includes("--dry-run");
if (!["ulmgap-dev", "ulmgap-prod"].includes(projectId) || !file) {
  console.error("Usage : --project ulmgap-dev|ulmgap-prod --file <caisse.csv> [--dry-run]");
  process.exit(1);
}

// Module compilé : lancer `npm run build` avant ce script.
const { importCashbox, parseCashCsv } = require("../lib/admin/import-cashbox");
const rows = parseCashCsv(fs.readFileSync(file, "utf8"));
const total = rows.reduce((s, r) => s + r.amount, 0);
console.log(`${rows.length} opérations lues, solde calculé : ${total} FCFA.`);
if (dryRun) process.exit(0);

admin.initializeApp({ projectId });
importCashbox(admin.firestore(), rows)
  .then(({ count, balance }) => console.log(`${count} opérations importées dans ${projectId}. Solde : ${balance} FCFA.`))
  .catch((e) => { console.error(e.message); process.exit(1); });
