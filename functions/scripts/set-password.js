// Définit directement le mot de passe d'un compte existant (et marque son
// e-mail comme vérifié), sans passer par l'e-mail de réinitialisation.
// Usage :
//   node scripts/set-password.js --project ulmgap-prod --email moi@x.fr --password <mot de passe>
// Identifiants : gcloud auth application-default login (compte propriétaire du projet).
const admin = require("firebase-admin");

const arg = (k) => {
  const i = process.argv.indexOf(`--${k}`);
  return i > 0 ? process.argv[i + 1] : undefined;
};
const projectId = arg("project");
const email = (arg("email") || "").trim().toLowerCase();
const password = arg("password") || "";
if (!projectId || !email || password.length < 6) {
  console.error("Usage : --project <id> --email <e-mail> --password <6 caractères minimum>");
  process.exit(1);
}

admin.initializeApp({ projectId });

(async () => {
  const user = await admin.auth().getUserByEmail(email);
  await admin.auth().updateUser(user.uid, { password, emailVerified: true });
  console.log(`Mot de passe défini pour ${email} (${user.uid}) sur ${projectId}.`);
})().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
