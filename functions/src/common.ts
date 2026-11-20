import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { z } from "zod";
import { brandColorsFromPalette, extractPalette } from "./lib/colors";
import type { Brand, Role } from "./lib/types";

if (!getApps().length) initializeApp();

// Mumbai region for low latency in India. Imagen runs in IMAGEN_LOCATION (see lib/imagegen.ts).
setGlobalOptions({ region: "asia-south1", maxInstances: 20 });

export const db = getFirestore();
export const bucket = () => getStorage().bucket();

export function requireAuth(req: CallableRequest): string {
  if (!req.auth) throw new HttpsError("unauthenticated", "Please sign in first.");
  return req.auth.uid;
}

export function parse<T extends z.ZodType>(schema: T, data: unknown): z.infer<T> {
  const r = schema.safeParse(data);
  if (!r.success) throw new HttpsError("invalid-argument", r.error.issues.map((i) => i.message).join("; "));
  return r.data;
}

const ROLE_RANK: Record<Role, number> = { editor: 1, admin: 2, owner: 3 };

export async function requireRole(uid: string, workspaceId: string, min: Role = "editor") {
  const m = await db.doc(`workspaces/${workspaceId}/members/${uid}`).get();
  const role = m.get("role") as Role | undefined;
  if (!role || ROLE_RANK[role] < ROLE_RANK[min]) {
    throw new HttpsError("permission-denied", "You don't have access to this workspace.");
  }
  return role;
}

export async function loadBrand(workspaceId: string, brandId: string) {
  const ref = db.doc(`workspaces/${workspaceId}/brands/${brandId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Brand not found.");
  return { ref, brand: snap.data() as Brand };
}

export const ids = { workspaceId: z.string().min(1), brandId: z.string().min(1) };

/** Saves a logo image for the brand and sets brand colors from it. */
export async function saveLogoAndColors(workspaceId: string, brandId: string, image: Buffer, contentType = "image/png") {
  const ext = contentType.includes("jpeg") || contentType.includes("jpg") ? "jpeg" : "png";
  const logoPath = `workspaces/${workspaceId}/brands/${brandId}/logo.${ext}`;
  await bucket().file(logoPath).save(image, { contentType: `image/${ext}`, resumable: false });
  const palette = await extractPalette(image);
  const colors = brandColorsFromPalette(palette);
  await db.doc(`workspaces/${workspaceId}/brands/${brandId}`).update({
    logoPath,
    logoPalette: palette,
    colors,
    colorSource: "logo",
  });
  return { logoPath, palette, colors };
}
