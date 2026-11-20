/**
 * Connecting Facebook, Instagram and Google Business Profile.
 *
 * Flow:
 *  1. App calls startConnect → gets the platform's own login URL and opens it in the browser.
 *  2. User signs in on Facebook / Instagram / Google and approves access.
 *  3. The platform redirects to oauthCallback, which exchanges the code for tokens
 *     (stored encrypted, server-only) and discovers the user's Pages / accounts / locations,
 *     including any setup problems (personal Instagram, unverified Google profile...).
 *  4. The app, watching the connection document, shows the profiles and any guidance.
 *  5. selectProfile links the chosen profile to the brand and fills in missing brand details.
 *  6. refreshConnection ("Check again") re-reads profiles after the user fixes something.
 */
import { FieldValue } from "firebase-admin/firestore";
import { defineSecret, defineString } from "firebase-functions/params";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { z } from "zod";

import { db, ids, loadBrand, parse, requireAuth, requireRole, saveLogoAndColors } from "./common";
import { decrypt, encrypt, randomState } from "./lib/crypto";
import { facebookAuthUrl, facebookDiscover, facebookExchange } from "./lib/oauth/facebook";
import { googleAuthUrl, googleDiscover, googleExchange, googleRefresh } from "./lib/oauth/google";
import { instagramAuthUrl, instagramDiscover, instagramExchange, instagramRefresh } from "./lib/oauth/instagram";
import { ProviderError, type Candidate, type Discovery, type OAuthConfig, type Provider, type Tokens } from "./lib/oauth/types";

// ---- configuration (see README → "Connecting Facebook, Instagram and Google") ----
const META_APP_ID = defineString("META_APP_ID", { default: "" });
const INSTAGRAM_APP_ID = defineString("INSTAGRAM_APP_ID", { default: "" });
const GOOGLE_CLIENT_ID = defineString("GOOGLE_CLIENT_ID", { default: "" });
const META_GRAPH_VERSION = defineString("META_GRAPH_VERSION", { default: "v24.0" });
const OAUTH_REDIRECT_URI = defineString("OAUTH_REDIRECT_URI", { default: "" });
const META_APP_SECRET = defineSecret("META_APP_SECRET");
const INSTAGRAM_APP_SECRET = defineSecret("INSTAGRAM_APP_SECRET");
const GOOGLE_CLIENT_SECRET = defineSecret("GOOGLE_CLIENT_SECRET");
const TOKEN_ENCRYPTION_KEY = defineSecret("TOKEN_ENCRYPTION_KEY");
const SECRETS = [META_APP_SECRET, INSTAGRAM_APP_SECRET, GOOGLE_CLIENT_SECRET, TOKEN_ENCRYPTION_KEY];

const REGION = "asia-south1";

function redirectUri(): string {
  if (OAUTH_REDIRECT_URI.value()) return OAUTH_REDIRECT_URI.value();
  const project = process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT;
  return process.env.FUNCTIONS_EMULATOR === "true"
    ? `http://127.0.0.1:5001/${project}/${REGION}/oauthCallback`
    : `https://${REGION}-${project}.cloudfunctions.net/oauthCallback`;
}

function config(): OAuthConfig {
  return {
    redirectUri: redirectUri(),
    metaAppId: META_APP_ID.value(),
    metaAppSecret: META_APP_SECRET.value(),
    metaGraphVersion: META_GRAPH_VERSION.value(),
    instagramAppId: INSTAGRAM_APP_ID.value(),
    instagramAppSecret: INSTAGRAM_APP_SECRET.value(),
    googleClientId: GOOGLE_CLIENT_ID.value(),
    googleClientSecret: GOOGLE_CLIENT_SECRET.value(),
  };
}

function assertConfigured(provider: Provider, cfg: OAuthConfig) {
  const ok =
    provider === "google"
      ? cfg.googleClientId && cfg.googleClientSecret
      : provider === "instagram"
        ? cfg.instagramAppId && cfg.instagramAppSecret
        : cfg.metaAppId && cfg.metaAppSecret;
  if (!ok) {
    throw new HttpsError("failed-precondition", `Connecting ${label(provider)} isn't switched on yet. Please try again later.`);
  }
}

const label = (p: Provider) => ({ facebook: "Facebook", instagram: "Instagram", google: "Google" })[p];
const key = () => TOKEN_ENCRYPTION_KEY.value();

// Firestore layout (per brand):
//   brands/{bid}/connections/{provider}  readable by members: status, account, candidates, issues
//   brands/{bid}/private/{provider}      server-only: encrypted tokens
const connRef = (wid: string, bid: string, p: Provider) => db.doc(`workspaces/${wid}/brands/${bid}/connections/${p}`);
const privRef = (wid: string, bid: string, p: Provider) => db.doc(`workspaces/${wid}/brands/${bid}/private/${p}`);

const providerSchema = z.enum(["facebook", "instagram", "google"]);

// ---------- 1. start ----------

export const startConnect = onCall({ secrets: SECRETS }, async (req) => {
  const uid = requireAuth(req);
  const input = parse(
    z.object({ ...ids, provider: providerSchema, rerequest: z.boolean().optional() }),
    req.data,
  );
  await requireRole(uid, input.workspaceId);
  await loadBrand(input.workspaceId, input.brandId);
  const cfg = config();
  assertConfigured(input.provider, cfg);

  const state = randomState();
  await db.doc(`oauthStates/${state}`).set({
    uid,
    workspaceId: input.workspaceId,
    brandId: input.brandId,
    provider: input.provider,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Date.now() + 15 * 60 * 1000,
  });
  await connRef(input.workspaceId, input.brandId, input.provider).set(
    { provider: input.provider, status: "waiting", updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );

  const url =
    input.provider === "facebook"
      ? facebookAuthUrl(cfg, state, input.rerequest)
      : input.provider === "instagram"
        ? instagramAuthUrl(cfg, state)
        : googleAuthUrl(cfg, state);
  return { url };
});

// ---------- 2. callback from the platform ----------

async function discover(provider: Provider, accessToken: string, cfg: OAuthConfig): Promise<Discovery> {
  if (provider === "facebook") return facebookDiscover(cfg, accessToken, fetch);
  if (provider === "instagram") return instagramDiscover(accessToken, fetch);
  return googleDiscover(accessToken, fetch);
}

async function saveDiscovery(wid: string, bid: string, provider: Provider, d: Discovery, uid?: string) {
  const prev = (await connRef(wid, bid, provider).get()).get("selectedId") as string | undefined;
  const stillThere = prev && d.candidates.some((c) => c.id === prev);
  await connRef(wid, bid, provider).set({
    provider,
    status: d.issues.length && !d.candidates.length ? "problem" : "connected",
    accountName: d.accountName,
    candidates: d.candidates,
    issues: d.issues,
    missingPermissions: d.missingPermissions ?? [],
    selectedId: stillThere ? prev : null,
    ...(uid ? { connectedBy: uid } : {}),
    updatedAt: FieldValue.serverTimestamp(),
    checkedAt: FieldValue.serverTimestamp(),
  });
  if (d.candidateTokens && Object.keys(d.candidateTokens).length) {
    const enc = Object.fromEntries(Object.entries(d.candidateTokens).map(([k, v]) => [k, encrypt(v, key())]));
    await privRef(wid, bid, provider).set({ candidateTokens: enc }, { merge: true });
  }
}

async function saveTokens(wid: string, bid: string, provider: Provider, t: Tokens) {
  const existing = (await privRef(wid, bid, provider).get()).data() ?? {};
  await privRef(wid, bid, provider).set({
    accessToken: encrypt(t.accessToken, key()),
    // Google only returns a refresh token on first consent; keep the old one otherwise.
    refreshToken: t.refreshToken ? encrypt(t.refreshToken, key()) : (existing.refreshToken ?? null),
    expiresAt: t.expiresAt ?? null,
    userId: t.userId ?? null,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

/** Returns a working access token, refreshing it when it's close to expiry. */
async function accessTokenFor(wid: string, bid: string, provider: Provider, cfg: OAuthConfig): Promise<string> {
  const priv = (await privRef(wid, bid, provider).get()).data();
  if (!priv?.accessToken) throw new ProviderError("TOKEN_EXPIRED", "Not connected.");
  const token = decrypt(priv.accessToken, key());
  const expiresAt = priv.expiresAt as number | null;
  const soon = expiresAt && expiresAt - Date.now() < 5 * 60 * 1000;
  const refreshWindow = expiresAt && expiresAt - Date.now() < 7 * 24 * 3600 * 1000;

  if (provider === "google" && soon) {
    if (!priv.refreshToken) throw new ProviderError("TOKEN_EXPIRED", "Google login expired.");
    const t = await googleRefresh(cfg, decrypt(priv.refreshToken, key()), fetch);
    await saveTokens(wid, bid, provider, t);
    return t.accessToken;
  }
  if (provider === "instagram" && refreshWindow && !soon) {
    const t = await instagramRefresh(token, fetch);
    await saveTokens(wid, bid, provider, { ...t, userId: priv.userId ?? undefined });
    return t.accessToken;
  }
  if (soon) throw new ProviderError("TOKEN_EXPIRED", `${label(provider)} login expired.`);
  return token;
}

function page(title: string, message: string, ok: boolean) {
  const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title>
<style>body{font-family:system-ui,sans-serif;background:#f4f7f8;color:#123;display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:16px}
.card{background:#fff;border-radius:16px;padding:32px;max-width:420px;text-align:center;box-shadow:0 4px 24px rgba(0,0,0,.08)}
.icon{font-size:48px}h1{font-size:22px;margin:12px 0}p{line-height:1.5;color:#456}</style></head>
<body><div class="card"><div class="icon">${ok ? "✅" : "⚠️"}</div><h1>${esc(title)}</h1><p>${esc(message)}</p>
<p><b>You can close this window and go back to Neev Udaan.</b></p></div>
<script>setTimeout(function(){try{window.close()}catch(e){}},2500)</script></body></html>`;
}

export const oauthCallback = onRequest({ secrets: SECRETS, timeoutSeconds: 120 }, async (req, res) => {
  const state = String(req.query.state ?? "");
  const code = String(req.query.code ?? "");
  const error = String(req.query.error ?? req.query.error_reason ?? "");

  const stateRef = state ? db.doc(`oauthStates/${state}`) : null;
  const st = stateRef ? await stateRef.get() : null;
  if (!st?.exists || (st.get("expiresAt") as number) < Date.now()) {
    res.status(400).send(page("This link has expired", "Please start connecting again from the app.", false));
    return;
  }
  await stateRef!.delete(); // one-time use
  const { workspaceId: wid, brandId: bid, provider, uid } = st.data() as {
    workspaceId: string;
    brandId: string;
    provider: Provider;
    uid: string;
  };

  if (error || !code) {
    await connRef(wid, bid, provider).set(
      {
        provider,
        status: "problem",
        issues: ["LOGIN_CANCELLED"],
        candidates: [],
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    res.send(page(`${label(provider)} was not connected`, "Sign-in was cancelled. You can try again any time.", false));
    return;
  }

  try {
    const cfg = config();
    const tokens =
      provider === "facebook"
        ? await facebookExchange(cfg, code, fetch)
        : provider === "instagram"
          ? await instagramExchange(cfg, code, fetch)
          : await googleExchange(cfg, code, fetch);
    await saveTokens(wid, bid, provider, tokens);
    const d = await discover(provider, tokens.accessToken, cfg);
    await saveDiscovery(wid, bid, provider, d, uid);
    res.send(page(`${label(provider)} connected`, "Now choose your business profile in the app.", true));
  } catch (e) {
    logger.error("oauthCallback failed", { provider, error: e instanceof Error ? e.message : e, body: (e as any)?.body });
    const issue = e instanceof ProviderError ? e.issue : "UNKNOWN";
    await connRef(wid, bid, provider).set(
      { provider, status: "problem", issues: [issue], candidates: [], updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    res.status(500).send(page("Something went wrong", "We couldn't finish connecting. Please try again from the app.", false));
  }
});

// ---------- 3. "Check again" ----------

export const refreshConnection = onCall({ secrets: SECRETS, timeoutSeconds: 120 }, async (req) => {
  const uid = requireAuth(req);
  const { workspaceId: wid, brandId: bid, provider } = parse(z.object({ ...ids, provider: providerSchema }), req.data);
  await requireRole(uid, wid);
  const cfg = config();
  try {
    const token = await accessTokenFor(wid, bid, provider, cfg);
    const d = await discover(provider, token, cfg);
    await saveDiscovery(wid, bid, provider, d);
    return { ok: true };
  } catch (e) {
    if (e instanceof ProviderError) {
      await connRef(wid, bid, provider).set(
        { status: "problem", issues: [e.issue], updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
      return { ok: false, issue: e.issue };
    }
    logger.error("refreshConnection failed", e);
    throw new HttpsError("internal", `Couldn't check ${label(provider)} right now. Please try again.`);
  }
});

// ---------- 4. choose a profile ----------

const BLOCKING = new Set(["NOT_PAGE_ADMIN", "IG_PERSONAL_ACCOUNT"]);

export const selectProfile = onCall({ secrets: SECRETS, timeoutSeconds: 60, memory: "512MiB" }, async (req) => {
  const uid = requireAuth(req);
  const input = parse(
    z.object({
      ...ids,
      provider: providerSchema,
      candidateId: z.string().min(1),
      includeInstagram: z.boolean().default(true),
    }),
    req.data,
  );
  const { workspaceId: wid, brandId: bid, provider } = input;
  await requireRole(uid, wid);
  const { ref: brandRef, brand } = await loadBrand(wid, bid);
  const conn = await connRef(wid, bid, provider).get();
  const candidate = (conn.get("candidates") as Candidate[] | undefined)?.find((c) => c.id === input.candidateId);
  if (!candidate) throw new HttpsError("not-found", "That profile is no longer available. Tap Check again.");
  const blocking = candidate.issues.find((i) => BLOCKING.has(i));
  if (blocking) throw new HttpsError("failed-precondition", blocking);

  const channels: Record<string, unknown> = {};
  if (provider === "facebook") {
    channels["channels.facebook"] = { id: candidate.id, name: candidate.name, pictureUrl: candidate.pictureUrl ?? null };
    const igOk = candidate.instagram && !candidate.issues.includes("IG_PERMISSION_DECLINED");
    const current = (brand as any).channels?.instagram;
    if (input.includeInstagram && igOk) {
      channels["channels.instagram"] = {
        id: candidate.instagram!.id,
        username: candidate.instagram!.username,
        pictureUrl: candidate.instagram!.pictureUrl ?? null,
        via: "facebook",
        pageId: candidate.id,
      };
    } else if (current?.via === "facebook") {
      channels["channels.instagram"] = FieldValue.delete();
    }
  } else if (provider === "instagram") {
    channels["channels.instagram"] = {
      id: candidate.id,
      username: candidate.instagram?.username ?? candidate.name.replace(/^@/, ""),
      pictureUrl: candidate.pictureUrl ?? null,
      via: "instagram",
    };
  } else {
    channels["channels.google"] = {
      id: candidate.id,
      title: candidate.name,
      address: candidate.subtitle ?? null,
      verified: !candidate.issues.includes("NOT_VERIFIED"),
    };
  }

  // Fill in brand details the user hasn't set yet.
  const filled: string[] = [];
  const updates: Record<string, unknown> = { ...channels, updatedAt: FieldValue.serverTimestamp() };
  const b = brand as unknown as Record<string, unknown>;
  const empty = (k: string) => !b[k] || (typeof b[k] === "string" && !(b[k] as string).trim());
  const placeholderName = !b.setupComplete && (b.name === "My business" || empty("name"));
  if (placeholderName && provider !== "instagram") {
    updates.name = candidate.name;
    filled.push("name");
  }
  if ((!b.setupComplete && b.industry === "Other") || empty("industry")) {
    if (candidate.details.category) {
      updates.industry = candidate.details.category;
      filled.push("industry");
    }
  }
  for (const [field, value] of [
    ["phone", candidate.details.phone],
    ["website", candidate.details.website],
    ["location", candidate.details.address],
    ["description", candidate.details.about],
  ] as const) {
    if (value && empty(field)) {
      updates[field] = value;
      filled.push(field);
    }
  }
  await brandRef.update(updates);
  await conn.ref.update({ selectedId: candidate.id, status: "connected", updatedAt: FieldValue.serverTimestamp() });

  // Use the Page / Instagram profile picture as the logo if there isn't one yet.
  const pictureUrl = candidate.pictureUrl ?? candidate.instagram?.pictureUrl;
  if (!brand.logoPath && pictureUrl) {
    try {
      const r = await fetch(pictureUrl);
      const type = r.headers.get("content-type") ?? "";
      const buf = Buffer.from(await r.arrayBuffer());
      if (r.ok && type.startsWith("image/") && buf.length < 5 * 1024 * 1024) {
        await saveLogoAndColors(wid, bid, buf, type);
        filled.push("logo", "colors");
      }
    } catch (e) {
      logger.warn("Could not import profile picture as logo", e);
    }
  }
  return { filled };
});

// ---------- 5. disconnect ----------

export const disconnectProvider = onCall(async (req) => {
  const uid = requireAuth(req);
  const { workspaceId: wid, brandId: bid, provider } = parse(z.object({ ...ids, provider: providerSchema }), req.data);
  await requireRole(uid, wid, "admin");
  const { ref: brandRef, brand } = await loadBrand(wid, bid);
  const updates: Record<string, unknown> = { [`channels.${provider}`]: FieldValue.delete() };
  if (provider === "facebook" && (brand as any).channels?.instagram?.via === "facebook") {
    updates["channels.instagram"] = FieldValue.delete();
  }
  await brandRef.update(updates);
  await Promise.all([connRef(wid, bid, provider).delete(), privRef(wid, bid, provider).delete()]);
  return { ok: true };
});
