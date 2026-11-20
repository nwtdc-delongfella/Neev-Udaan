import { test } from "node:test";
import assert from "node:assert/strict";
import { decrypt, encrypt } from "../lib/crypto";
import { facebookAuthUrl, facebookDiscover, facebookExchange } from "../lib/oauth/facebook";
import { googleAuthUrl, googleDiscover } from "../lib/oauth/google";
import { instagramDiscover, instagramExchange } from "../lib/oauth/instagram";
import { ProviderError, type Fetcher, type OAuthConfig } from "../lib/oauth/types";

const cfg: OAuthConfig = {
  redirectUri: "https://example.test/oauthCallback",
  metaAppId: "meta-app",
  metaAppSecret: "meta-secret",
  metaGraphVersion: "v24.0",
  instagramAppId: "ig-app",
  instagramAppSecret: "ig-secret",
  googleClientId: "g-client",
  googleClientSecret: "g-secret",
};

/** Fake fetch: first route whose substring matches the URL answers. */
function fakeFetch(routes: [string, number, unknown][]): Fetcher & { calls: string[] } {
  const calls: string[] = [];
  const f = (async (input: any) => {
    const url = String(input);
    calls.push(url);
    const r = routes.find(([m]) => url.includes(m));
    if (!r) throw new Error(`unexpected request ${url}`);
    return new Response(JSON.stringify(r[2]), { status: r[1], headers: { "content-type": "application/json" } });
  }) as Fetcher & { calls: string[] };
  f.calls = calls;
  return f;
}

const allPerms = [
  "public_profile",
  "pages_show_list",
  "pages_read_engagement",
  "pages_manage_posts",
  "business_management",
  "instagram_basic",
  "instagram_content_publish",
].map((permission) => ({ permission, status: "granted" }));

test("token encryption round-trips and detects tampering", () => {
  const k = Buffer.alloc(32, 7).toString("base64");
  const sealed = encrypt("secret-token", k);
  assert.notEqual(sealed, "secret-token");
  assert.equal(decrypt(sealed, k), "secret-token");
  const bad = Buffer.from(sealed, "base64");
  bad[bad.length - 1] ^= 1;
  assert.throws(() => decrypt(bad.toString("base64"), k));
});

test("auth URLs carry state, redirect and scopes", () => {
  const fb = new URL(facebookAuthUrl(cfg, "abc", true));
  assert.equal(fb.searchParams.get("state"), "abc");
  assert.equal(fb.searchParams.get("redirect_uri"), cfg.redirectUri);
  assert.equal(fb.searchParams.get("auth_type"), "rerequest");
  assert.ok(fb.searchParams.get("scope")!.includes("instagram_content_publish"));
  const g = new URL(googleAuthUrl(cfg, "xyz"));
  assert.equal(g.searchParams.get("access_type"), "offline");
  assert.ok(g.searchParams.get("scope")!.includes("business.manage"));
});

test("facebook: exchanges code for a long-lived token", async () => {
  const f = fakeFetch([
    ["fb_exchange_token", 200, { access_token: "LONG", expires_in: 5184000 }],
    ["oauth/access_token", 200, { access_token: "SHORT" }],
  ]);
  const t = await facebookExchange(cfg, "CODE", f);
  assert.equal(t.accessToken, "LONG");
  assert.ok(t.expiresAt! > Date.now());
});

test("facebook: lists Pages with linked Instagram and flags problems", async () => {
  const f = fakeFetch([
    ["/me/permissions", 200, { data: allPerms }],
    ["/me/accounts", 200, {
      data: [
        {
          id: "p1", name: "Sunrise Bakery", category: "Bakery", access_token: "PT1", tasks: ["MANAGE", "CREATE_CONTENT"],
          phone: "+91 98765 43210", website: "https://sunrise.example", single_line_address: "MG Road, Pune",
          picture: { data: { url: "https://cdn.example/p1.jpg" } },
          instagram_business_account: { id: "ig1", username: "sunrisebakery" },
        },
        { id: "p2", name: "Old Page", access_token: "PT2", tasks: ["ANALYZE"] },
        { id: "p3", name: "No IG Page", access_token: "PT3", tasks: ["CREATE_CONTENT"] },
      ],
    }],
    ["/me?fields=name", 200, { name: "Asha" }],
  ]);
  const d = await facebookDiscover(cfg, "USER", f);
  assert.deepEqual(d.issues, []);
  assert.equal(d.accountName, "Asha");
  const [p1, p2, p3] = d.candidates;
  assert.deepEqual(p1.issues, []);
  assert.equal(p1.instagram?.username, "sunrisebakery");
  assert.equal(p1.details.address, "MG Road, Pune");
  assert.ok(p2.issues.includes("NOT_PAGE_ADMIN"));
  assert.deepEqual(p3.issues, ["IG_NOT_LINKED"]);
  assert.equal(d.candidateTokens?.p1, "PT1");
});

test("facebook: no Pages and unticked permissions are reported", async () => {
  const noPages = await facebookDiscover(cfg, "U", fakeFetch([
    ["/me/permissions", 200, { data: allPerms }],
    ["/me/accounts", 200, { data: [] }],
    ["/me?fields=name", 200, { name: "A" }],
  ]));
  assert.deepEqual(noPages.issues, ["NO_PAGES"]);

  const declined = await facebookDiscover(cfg, "U", fakeFetch([
    ["/me/permissions", 200, { data: allPerms.map((p) => p.permission === "pages_manage_posts" || p.permission === "instagram_content_publish" ? { ...p, status: "declined" } : p) }],
    ["/me/accounts", 200, { data: [{ id: "p1", name: "X", tasks: ["CREATE_CONTENT"], instagram_business_account: { id: "i" } }] }],
    ["/me?fields=name", 200, { name: "A" }],
  ]));
  assert.deepEqual(declined.issues, ["PERMISSIONS_MISSING"]);
  assert.deepEqual(declined.missingPermissions, ["pages_manage_posts", "instagram_content_publish"]);
  assert.ok(declined.candidates[0].issues.includes("IG_PERMISSION_DECLINED"));
});

test("facebook: expired token becomes TOKEN_EXPIRED", async () => {
  const f = fakeFetch([["/me", 400, { error: { code: 190, message: "expired" } }]]);
  await assert.rejects(facebookDiscover(cfg, "U", f), (e) => e instanceof ProviderError && e.issue === "TOKEN_EXPIRED");
});

test("instagram: exchange strips '#_' and detects personal accounts", async () => {
  const f = fakeFetch([
    ["api.instagram.com/oauth/access_token", 200, { access_token: "S", user_id: 42 }],
    ["ig_exchange_token", 200, { access_token: "L", expires_in: 5184000 }],
  ]);
  const t = await instagramExchange(cfg, "CODE#_", f);
  assert.equal(t.accessToken, "L");
  assert.equal(t.userId, "42");

  const personal = await instagramDiscover("L", fakeFetch([["graph.instagram.com/me", 200, { user_id: "42", username: "asha", account_type: "PERSONAL" }]]));
  assert.deepEqual(personal.candidates[0].issues, ["IG_PERSONAL_ACCOUNT"]);
  const biz = await instagramDiscover("L", fakeFetch([["graph.instagram.com/me", 200, { user_id: "42", username: "shop", account_type: "BUSINESS" }]]));
  assert.deepEqual(biz.candidates[0].issues, []);
});

test("google: lists locations, flags unverified ones", async () => {
  const f = fakeFetch([
    ["userinfo", 200, { email: "owner@example.com" }],
    ["/v1/accounts?", 200, { accounts: [{ name: "accounts/1", accountName: "Owner" }] }],
    ["accounts/1/locations", 200, {
      locations: [
        { name: "locations/10", title: "Sunrise Bakery", websiteUri: "https://sunrise.example", phoneNumbers: { primaryPhone: "020 1234" },
          storefrontAddress: { addressLines: ["12 MG Road"], locality: "Pune", postalCode: "411001" },
          categories: { primaryCategory: { displayName: "Bakery" } }, metadata: { hasVoiceOfMerchant: true } },
        { name: "locations/11", title: "New Branch", metadata: { hasVoiceOfMerchant: false } },
      ],
    }],
  ]);
  const d = await googleDiscover("AT", f);
  assert.equal(d.accountName, "owner@example.com");
  assert.equal(d.candidates.length, 2);
  assert.equal(d.candidates[0].id, "accounts/1/locations/10");
  assert.equal(d.candidates[0].details.address, "12 MG Road, Pune, 411001");
  assert.deepEqual(d.candidates[0].issues, []);
  assert.deepEqual(d.candidates[1].issues, ["NOT_VERIFIED"]);
});

test("google: no profiles, and API access not yet approved", async () => {
  const none = await googleDiscover("AT", fakeFetch([
    ["userinfo", 200, { email: "x@example.com" }],
    ["/v1/accounts?", 200, { accounts: [{ name: "accounts/1" }] }],
    ["accounts/1/locations", 200, {}],
  ]));
  assert.deepEqual(none.issues, ["NO_LOCATIONS"]);

  const pending = await googleDiscover("AT", fakeFetch([
    ["userinfo", 200, { email: "x@example.com" }],
    ["/v1/accounts?", 429, { error: { code: 429, message: "Quota exceeded for quota metric 'Requests' ... limit 0", status: "RESOURCE_EXHAUSTED" } }],
  ]));
  assert.deepEqual(pending.issues, ["API_NOT_APPROVED"]);
});
