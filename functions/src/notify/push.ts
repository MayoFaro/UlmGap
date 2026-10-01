// Envoi des notifications push par FCM (spec §6.1, plan 5). Appelé après la
// réussite d'une action : un échec est journalisé et n'annule jamais
// l'action, d'où une fonction qui ne lève jamais. Les jetons que FCM déclare
// invalides sont effacés (`users.fcmToken: null`).
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { Push, PushMessage } from "../rules/notifications";

type Db = FirebaseFirestore.Firestore;

export type Sender = (tokens: string[], m: PushMessage) =>
  Promise<{ failedTokens: string[]; invalidTokens: string[] }>;

const INVALID = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

const fcmSender: Sender = async (tokens, m) => {
  const r = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title: m.title, body: m.body },
    webpush: { fcmOptions: { link: "/" } },
  });
  const failedTokens: string[] = [];
  const invalidTokens: string[] = [];
  r.responses.forEach((res, i) => {
    if (res.success) return;
    failedTokens.push(tokens[i]);
    if (res.error && INVALID.has(res.error.code)) invalidTokens.push(tokens[i]);
  });
  return { failedTokens, invalidTokens };
};

let sender: Sender = fcmSender;

/** L'émulateur n'a pas FCM : les tests remplacent l'envoi (null = FCM). */
export function setPushSenderForTests(s: Sender | null): void {
  sender = s ?? fcmSender;
}

/** Envoie [push] aux comptes actifs qui ont un jeton. Ne lève jamais. */
export async function sendPush(db: Db, push: Push | null): Promise<void> {
  if (!push || push.to.length === 0) return;
  try {
    const snaps = await db.getAll(...push.to.map((u) => db.collection("users").doc(u)));
    const byToken = new Map<string, string>();
    for (const s of snaps) {
      const token = s.get("fcmToken");
      if (s.exists && s.get("active") === true && typeof token === "string" && token) {
        byToken.set(token, s.id);
      }
    }
    if (byToken.size === 0) return;
    const r = await sender([...byToken.keys()], push.message);
    if (r.failedTokens.length > 0) {
      logger.warn("Notifications non remises", { title: push.message.title, failed: r.failedTokens.length });
    }
    await Promise.all(r.invalidTokens.map((t) =>
      db.collection("users").doc(byToken.get(t)!).update({ fcmToken: null })));
  } catch (e) {
    logger.error("Échec de l'envoi des notifications", { title: push.message.title, error: String(e) });
  }
}
