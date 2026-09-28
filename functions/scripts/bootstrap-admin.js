// Crée (ou promeut) le premier admin d'un projet. Usage :
//   node scripts/bootstrap-admin.js --project ulmgap-dev --email moi@x.fr --name "Nom" --short ABC
// Identifiants : gcloud auth application-default login (compte propriétaire du projet).
const admin = require("firebase-admin");

const arg = (k) => {
  const i = process.argv.indexOf(`--${k}`);
  return i > 0 ? process.argv[i + 1] : undefined;
};
const projectId = arg("project");
const email = (arg("email") || "").trim().toLowerCase();
const name = arg("name") || email;
const short = (arg("short") || "").toUpperCase();
if (!projectId || !email || !/^[A-Z0-9]{2,4}$/.test(short)) {
  console.error("Usage : --project <id> --email <e-mail> --name <nom> --short <2-4 car.>");
  process.exit(1);
}

admin.initializeApp({ projectId });
(async () => {
  let rec;
  try {
    rec = await admin.auth().getUserByEmail(email);
  } catch {
    rec = await admin.auth().createUser({ email, displayName: name });
  }
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.collection("users").doc(rec.uid).set({
    email, displayName: name, shortName: short, profile: null, category: "GAP",
    isAdmin: true, active: true, balance: 0, fcmToken: null, createdAt: now, updatedAt: now,
  }, { merge: true });
  await db.collection("profiles").doc(rec.uid).set(
    { displayName: name, shortName: short, profile: null, active: true }, { merge: true });
  const link = await admin.auth().generatePasswordResetLink(email);
  console.log(`Admin prêt : ${email} (uid ${rec.uid}).`);
  console.log(`Lien pour définir le mot de passe : ${link}`);
})().catch((e) => { console.error(e.message); process.exit(1); });
