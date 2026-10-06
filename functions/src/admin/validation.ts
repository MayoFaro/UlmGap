// Validation (pure) des entrées des fonctions d'administration.
// Codes identiques à lib/core/profiles.dart (fixture test/fixtures/referentials.json).
export const PROFILES = ["instructeur", "lache_toute_mission", "lache_solo", "eleve"] as const;
export const CATEGORIES = ["GAP", "GR", "MIL", "EXT"] as const;
export type Profile = typeof PROFILES[number];
export type Category = typeof CATEGORIES[number];

export class ValidationError extends Error {}

export interface UserInput {
  email: string;
  displayName: string;
  shortName: string;
  profile: Profile | null;
  category: Category;
  isAdmin: boolean;
  active: boolean;
  amphibiousCleared: boolean;
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SHORT_RE = /^[A-Z0-9]{2,4}$/;

export function obj(data: unknown): Record<string, unknown> {
  if (!data || typeof data !== "object") throw new ValidationError("Données manquantes.");
  return data as Record<string, unknown>;
}

export function text(v: unknown, field: string, max: number): string {
  const s = typeof v === "string" ? v.trim() : "";
  if (!s || s.length > max) throw new ValidationError(`${field} invalide.`);
  return s;
}

export function bool(v: unknown, field: string, dflt: boolean): boolean {
  if (v === undefined) return dflt;
  if (typeof v !== "boolean") throw new ValidationError(`${field} invalide.`);
  return v;
}

function shortName(v: unknown): string {
  const s = typeof v === "string" ? v.trim().toUpperCase() : "";
  if (!SHORT_RE.test(s)) throw new ValidationError("Code court invalide (2 à 4 lettres ou chiffres).");
  return s;
}

function profile(v: unknown): Profile | null {
  if (v === null || v === undefined) return null;
  if (!PROFILES.includes(v as Profile)) throw new ValidationError("Profil invalide.");
  return v as Profile;
}

function category(v: unknown): Category {
  if (!CATEGORIES.includes(v as Category)) throw new ValidationError("Appartenance invalide.");
  return v as Category;
}

export function validateNewUser(data: unknown): UserInput {
  const d = obj(data);
  const email = typeof d.email === "string" ? d.email.trim().toLowerCase() : "";
  if (!EMAIL_RE.test(email)) throw new ValidationError("E-mail invalide.");
  return {
    email,
    displayName: text(d.displayName, "Nom", 80),
    shortName: shortName(d.shortName),
    profile: profile(d.profile),
    category: category(d.category),
    isAdmin: bool(d.isAdmin, "Admin", false),
    active: bool(d.active, "Actif", true),
    amphibiousCleared: bool(d.amphibiousCleared, "Lâché amphibie", false),
  };
}

export function validateUserPatch(data: unknown): {
  uid: string; patch: Partial<Omit<UserInput, "email">>;
} {
  const d = obj(data);
  const uid = typeof d.uid === "string" ? d.uid.trim() : "";
  if (!uid) throw new ValidationError("Utilisateur manquant.");
  if ("email" in d) throw new ValidationError("L'e-mail ne peut pas être modifié.");
  const patch: Partial<Omit<UserInput, "email">> = {};
  if ("displayName" in d) patch.displayName = text(d.displayName, "Nom", 80);
  if ("shortName" in d) patch.shortName = shortName(d.shortName);
  if ("profile" in d) patch.profile = profile(d.profile);
  if ("category" in d) patch.category = category(d.category);
  if ("isAdmin" in d) patch.isAdmin = bool(d.isAdmin, "Admin", false);
  if ("active" in d) patch.active = bool(d.active, "Actif", true);
  if ("amphibiousCleared" in d) {
    patch.amphibiousCleared = bool(d.amphibiousCleared, "Lâché amphibie", false);
  }
  if (Object.keys(patch).length === 0) throw new ValidationError("Aucune modification.");
  return { uid, patch };
}

export function validateAircraft(data: unknown): {
  id?: string; registration: string; label: string; active: boolean; amphibious: boolean;
} {
  const d = obj(data);
  const registration = text(d.registration, "Immatriculation", 12).toUpperCase();
  // Sert d'identifiant de document (aircraftRegistrations) : pas de « / ».
  if (!/^[A-Z0-9-]+$/.test(registration)) {
    throw new ValidationError("Immatriculation invalide (lettres, chiffres et tirets).");
  }
  const out: { id?: string; registration: string; label: string; active: boolean; amphibious: boolean } = {
    registration,
    label: text(d.label, "Libellé", 40),
    active: bool(d.active, "Actif", true),
    amphibious: bool(d.amphibious, "Amphibie", false),
  };
  if (typeof d.id === "string" && d.id.trim()) out.id = d.id.trim();
  return out;
}
