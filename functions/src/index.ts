import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall, type CallableRequest } from "firebase-functions/v2/https";
import { onDocumentDeleted } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { z } from "zod";

import { brandColorsFromPalette, extractPalette, readableOn } from "./lib/colors";
import { composePost } from "./lib/compose";
import { generateIdeas as claudeIdeas, type Idea } from "./lib/ideas";
import { buildImagePrompt, ImagenGenerator, type ImageGenerator } from "./lib/imagegen";
import { DEFAULT_FORMAT, FORMATS, PLAN_LIMITS, type Brand, type Format, type Layout, type Role } from "./lib/types";

initializeApp();
const db = getFirestore();
const bucket = () => getStorage().bucket();

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

// Mumbai region for low latency in India. Imagen runs in IMAGEN_LOCATION (see imagegen.ts).
setGlobalOptions({ region: "asia-south1", maxInstances: 20 });

let imageGen: ImageGenerator | undefined;
const getImageGen = () => (imageGen ??= new ImagenGenerator());

// ---------- helpers ----------

function requireAuth(req: CallableRequest): string {
  if (!req.auth) throw new HttpsError("unauthenticated", "Please sign in first.");
  return req.auth.uid;
}

function parse<T extends z.ZodType>(schema: T, data: unknown): z.infer<T> {
  const r = schema.safeParse(data);
  if (!r.success) throw new HttpsError("invalid-argument", r.error.issues.map((i) => i.message).join("; "));
  return r.data;
}

const ROLE_RANK: Record<Role, number> = { editor: 1, admin: 2, owner: 3 };

async function requireRole(uid: string, workspaceId: string, min: Role = "editor") {
  const m = await db.doc(`workspaces/${workspaceId}/members/${uid}`).get();
  const role = m.get("role") as Role | undefined;
  if (!role || ROLE_RANK[role] < ROLE_RANK[min]) {
    throw new HttpsError("permission-denied", "You don't have access to this workspace.");
  }
  return role;
}

async function loadBrand(workspaceId: string, brandId: string) {
  const ref = db.doc(`workspaces/${workspaceId}/brands/${brandId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Brand not found.");
  return { ref, brand: snap.data() as Brand };
}

const monthKey = () => new Date().toISOString().slice(0, 7);

/** Reserves one image from the workspace's monthly allowance, atomically. */
async function reserveImage(workspaceId: string) {
  const wsRef = db.doc(`workspaces/${workspaceId}`);
  const usageRef = db.doc(`workspaces/${workspaceId}/usage/${monthKey()}`);
  await db.runTransaction(async (tx) => {
    const [ws, usage] = await Promise.all([tx.get(wsRef), tx.get(usageRef)]);
    const limit = PLAN_LIMITS[ws.get("plan") ?? "free"]?.imagesPerMonth ?? 0;
    const used = usage.get("images") ?? 0;
    if (used >= limit) {
      throw new HttpsError("resource-exhausted", `You've used all ${limit} images in your plan this month.`);
    }
    tx.set(usageRef, { images: used + 1, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  });
  return () => usageRef.set({ images: FieldValue.increment(-1) }, { merge: true }); // refund on failure
}

const ids = { workspaceId: z.string().min(1), brandId: z.string().min(1) };

// ---------- 1. Onboarding ----------

/** Creates a workspace, makes the caller its owner, and creates the first brand. */
export const createWorkspace = onCall(async (req) => {
  const uid = requireAuth(req);
  const input = parse(
    z.object({
      workspaceName: z.string().trim().min(2).max(80),
      brandName: z.string().trim().min(2).max(80),
      industry: z.string().trim().min(2).max(80),
    }),
    req.data,
  );

  const wsRef = db.collection("workspaces").doc();
  const brandRef = wsRef.collection("brands").doc();
  const batch = db.batch();
  batch.set(wsRef, {
    name: input.workspaceName,
    ownerUid: uid,
    plan: "free",
    createdAt: FieldValue.serverTimestamp(),
  });
  batch.set(wsRef.collection("members").doc(uid), {
    role: "owner",
    email: req.auth?.token.email ?? null,
    joinedAt: FieldValue.serverTimestamp(),
  });
  const colors = brandColorsFromPalette([]);
  batch.set(brandRef, {
    name: input.brandName,
    industry: input.industry,
    tone: "friendly and professional",
    colors,
    colorSource: "custom",
    createdAt: FieldValue.serverTimestamp(),
  } satisfies Brand & { createdAt: unknown });
  batch.set(
    db.doc(`users/${uid}`),
    { email: req.auth?.token.email ?? null, defaultWorkspaceId: wsRef.id, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  await batch.commit();
  return { workspaceId: wsRef.id, brandId: brandRef.id };
});

/** Adds another brand (business / location) to a workspace, within the plan's limit. */
export const createBrand = onCall(async (req) => {
  const uid = requireAuth(req);
  const input = parse(
    z.object({
      workspaceId: z.string().min(1),
      name: z.string().trim().min(2).max(80),
      industry: z.string().trim().min(2).max(80),
    }),
    req.data,
  );
  await requireRole(uid, input.workspaceId, "admin");
  const wsRef = db.doc(`workspaces/${input.workspaceId}`);
  const brandRef = wsRef.collection("brands").doc();
  await db.runTransaction(async (tx) => {
    const ws = await tx.get(wsRef);
    const count = (await tx.get(wsRef.collection("brands").count())).data().count;
    const limit = PLAN_LIMITS[ws.get("plan") ?? "free"]?.brands ?? 1;
    if (count >= limit) {
      throw new HttpsError("resource-exhausted", `Your plan allows ${limit} brand(s). Upgrade to add more.`);
    }
    tx.set(brandRef, {
      name: input.name,
      industry: input.industry,
      tone: "friendly and professional",
      colors: brandColorsFromPalette([]),
      colorSource: "custom",
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { brandId: brandRef.id };
});

// ---------- 2. Brand colors from logo ----------

/** Reads the brand's uploaded logo and returns its dominant colors plus suggested roles. */
export const extractBrandColors = onCall({ memory: "512MiB" }, async (req) => {
  const uid = requireAuth(req);
  const { workspaceId, brandId } = parse(z.object(ids), req.data);
  await requireRole(uid, workspaceId);
  const { ref, brand } = await loadBrand(workspaceId, brandId);
  if (!brand.logoPath?.startsWith(`workspaces/${workspaceId}/`)) {
    throw new HttpsError("failed-precondition", "Upload a logo first.");
  }
  const [logo] = await bucket().file(brand.logoPath).download();
  const palette = await extractPalette(logo);
  const suggested = brandColorsFromPalette(palette);
  await ref.update({ logoPalette: palette });
  return { palette, suggested };
});

// ---------- 3. Post ideas (Claude) ----------

export const generateIdeas = onCall(
  { secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 180, memory: "512MiB" },
  async (req) => {
    const uid = requireAuth(req);
    const input = parse(
      z.object({
        ...ids,
        topic: z.string().trim().min(3, "Describe the topic in a few words.").max(500),
        platform: z.enum(["instagram", "facebook", "google"]),
        count: z.number().int().min(3).max(8).default(6),
      }),
      req.data,
    );
    await requireRole(uid, input.workspaceId);
    const { ref, brand } = await loadBrand(input.workspaceId, input.brandId);

    let ideas: Idea[];
    try {
      ideas = await claudeIdeas({ brand, topic: input.topic, platform: input.platform, count: input.count });
    } catch (e) {
      logger.error("generateIdeas failed", e);
      throw new HttpsError("internal", e instanceof Error ? e.message : "Could not generate ideas.");
    }

    const setRef = ref.collection("ideaSets").doc();
    await setRef.set({
      topic: input.topic,
      platform: input.platform,
      ideas,
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    await db
      .doc(`workspaces/${input.workspaceId}/usage/${monthKey()}`)
      .set({ ideaRequests: FieldValue.increment(1) }, { merge: true });
    return { ideaSetId: setRef.id, ideas };
  },
);

// ---------- 4. Generate the image post ----------

const layoutSchema = z.enum(["band", "top", "minimal"]);
const formatSchema = z.enum(["square", "portrait", "landscape"]);

function footerFor(brand: Brand) {
  return [brand.website, brand.phone].filter(Boolean).join("  •  ") || undefined;
}

async function renderAndSave(opts: {
  workspaceId: string;
  brandId: string;
  postId: string;
  brand: Brand;
  background: Buffer;
  format: Format;
  layout: Layout;
  headline: string;
  subline?: string;
}) {
  const { width, height } = FORMATS[opts.format];
  const logo = opts.brand.logoPath ? (await bucket().file(opts.brand.logoPath).download())[0] : undefined;
  const colors = { ...opts.brand.colors, onPrimary: readableOn(opts.brand.colors.primary) };
  const png = await composePost({
    background: opts.background,
    logo,
    width,
    height,
    colors,
    headline: opts.headline,
    subline: opts.subline,
    footer: footerFor(opts.brand),
    layout: opts.layout,
  });
  const imagePath = `workspaces/${opts.workspaceId}/brands/${opts.brandId}/posts/${opts.postId}/post-${Date.now()}.png`;
  await bucket().file(imagePath).save(png, { contentType: "image/png", resumable: false });
  return imagePath;
}

/** Generates a background with Imagen, adds the logo and headline, and stores the post. */
export const generatePost = onCall({ timeoutSeconds: 300, memory: "1GiB" }, async (req) => {
  const uid = requireAuth(req);
  const input = parse(
    z.object({
      ...ids,
      ideaSetId: z.string().min(1),
      ideaIndex: z.number().int().min(0),
      format: formatSchema.optional(),
      layout: layoutSchema.default("band"),
      headline: z.string().trim().max(120).optional(),
      subline: z.string().trim().max(160).optional(),
    }),
    req.data,
  );
  await requireRole(uid, input.workspaceId);
  const { ref: brandRef, brand } = await loadBrand(input.workspaceId, input.brandId);
  const set = await brandRef.collection("ideaSets").doc(input.ideaSetId).get();
  const idea = (set.get("ideas") as Idea[] | undefined)?.[input.ideaIndex];
  if (!idea) throw new HttpsError("not-found", "Idea not found.");

  const platform = set.get("platform") as keyof typeof DEFAULT_FORMAT;
  const format = input.format ?? DEFAULT_FORMAT[platform];
  const postRef = brandRef.collection("posts").doc();
  const headline = input.headline || idea.headline;
  const subline = input.subline ?? idea.subline;

  const refund = await reserveImage(input.workspaceId);
  await postRef.set({
    status: "generating",
    platform,
    format,
    layout: input.layout,
    topic: set.get("topic"),
    ideaSetId: input.ideaSetId,
    ideaIndex: input.ideaIndex,
    title: idea.title,
    headline,
    subline,
    caption: idea.caption,
    hashtags: idea.hashtags,
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
  });

  try {
    const background = await getImageGen().generate(
      buildImagePrompt(idea.imagePrompt, brand.colors),
      FORMATS[format].aspect,
    );
    const backgroundPath = `workspaces/${input.workspaceId}/brands/${input.brandId}/posts/${postRef.id}/background.png`;
    await bucket().file(backgroundPath).save(background, { contentType: "image/png", resumable: false });
    const imagePath = await renderAndSave({
      workspaceId: input.workspaceId,
      brandId: input.brandId,
      postId: postRef.id,
      brand,
      background,
      format,
      layout: input.layout,
      headline,
      subline,
    });
    await postRef.update({ status: "ready", imagePath, backgroundPath, updatedAt: FieldValue.serverTimestamp() });
    return { postId: postRef.id, imagePath };
  } catch (e) {
    logger.error("generatePost failed", e);
    await refund();
    const message = e instanceof HttpsError ? e.message : e instanceof Error ? e.message : "Image generation failed.";
    await postRef.update({ status: "failed", error: message });
    throw new HttpsError("internal", message);
  }
});

/**
 * Re-renders an existing post with a new layout/headline/colors, reusing its AI
 * background. Free: it does not count against the monthly image allowance.
 */
export const relayoutPost = onCall({ timeoutSeconds: 60, memory: "1GiB" }, async (req) => {
  const uid = requireAuth(req);
  const input = parse(
    z.object({
      ...ids,
      postId: z.string().min(1),
      layout: layoutSchema.optional(),
      headline: z.string().trim().max(120).optional(),
      subline: z.string().trim().max(160).optional(),
    }),
    req.data,
  );
  await requireRole(uid, input.workspaceId);
  const { ref: brandRef, brand } = await loadBrand(input.workspaceId, input.brandId);
  const postRef = brandRef.collection("posts").doc(input.postId);
  const post = await postRef.get();
  if (!post.exists || !post.get("backgroundPath")) throw new HttpsError("not-found", "Post not found.");

  const [background] = await bucket().file(post.get("backgroundPath")).download();
  const layout = input.layout ?? post.get("layout");
  const headline = input.headline ?? post.get("headline");
  const subline = input.subline ?? post.get("subline");
  const imagePath = await renderAndSave({
    workspaceId: input.workspaceId,
    brandId: input.brandId,
    postId: input.postId,
    brand,
    background,
    format: post.get("format"),
    layout,
    headline,
    subline,
  });
  const old = post.get("imagePath") as string | undefined;
  await postRef.update({ imagePath, layout, headline, subline, updatedAt: FieldValue.serverTimestamp() });
  if (old && old !== imagePath) await bucket().file(old).delete({ ignoreNotFound: true });
  return { imagePath };
});

/** Removes a post's images from Storage when the post is deleted in the app. */
export const cleanupPostFiles = onDocumentDeleted(
  "workspaces/{workspaceId}/brands/{brandId}/posts/{postId}",
  async (event) => {
    const { workspaceId, brandId, postId } = event.params;
    await bucket().deleteFiles({ prefix: `workspaces/${workspaceId}/brands/${brandId}/posts/${postId}/` });
  },
);
