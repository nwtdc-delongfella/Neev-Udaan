# Neev Udaan

AI social media posts and Google review replies for any business. The app works on Android, iOS, macOS, Windows and the web.

**Phase 1 (this code):**
- Sign up and sign in.
- Workspaces with roles.
- Brand setup: logo upload, colors taken automatically from the logo or chosen by hand, and tone of voice.
- **Topic → AI post ideas → image post.** The image is AI generated, with the real logo and the headline placed on top.
- Free re-layouts of a post, a post library, and share or download.
- A monthly image allowance per plan.

**Later phases:** posting directly to Instagram, Facebook and Google Business Profile (Phase 2), Google review alerts with AI replies (Phase 3), and billing and team invites (Phase 4).

| Layout "band" (square) | Layout "top" (portrait) |
|---|---|
| ![](docs/samples/band-square.png) | ![](docs/samples/top-portrait.png) |

*These samples use a placeholder background. In the app, Imagen generates the photo.*

## How it works

```
Flutter app (app/)                      Firebase / Google Cloud (functions/)
─────────────────                       ─────────────────────────────────────
Sign in (Firebase Auth)
Brand setup ── upload logo ──► Storage
            ── extractBrandColors ────► k-means palette from logo (sharp)
Create ─────── generateIdeas ─────────► Claude (structured JSON ideas + captions)
       ─────── generatePost ──────────► Imagen (background, no text)
                                        └► compositor: logo + headline + brand colors
                                           (sharp + resvg, Poppins font) → Storage
Post ───────── relayoutPost ──────────► re-render, same background (free)
```

- **Why the logo isn't drawn by the AI:** image models distort logos and misspell text. Imagen produces only the scene. The app places the real logo file and the headline text, so the brand always looks right.
- **Security:** AI output, usage counters, plans and memberships can only be written by Cloud Functions. The app can edit only an allow-listed set of brand fields. All of this is enforced in `firestore.rules` and `storage.rules`.
- **Region:** functions run in `asia-south1` (Mumbai). Imagen runs in `us-central1`; change this with `IMAGEN_LOCATION`.

### Data model (Firestore)

```
users/{uid}                         defaultWorkspaceId
workspaces/{wid}                    name, ownerUid, plan
  members/{uid}                     role: owner | admin | editor
  usage/{YYYY-MM}                   images, ideaRequests
  brands/{bid}                      name, industry, tone, audience, location, language,
                                    website, phone, logoPath, colors{primary,secondary,accent,onPrimary}
    ideaSets/{id}                   topic, platform, ideas[]
    posts/{id}                      status, platform, format, layout, headline, caption,
                                    hashtags, imagePath, backgroundPath
```

Phase 2 will add `brands/{bid}/connections/{platform}`, which holds encrypted tokens server-side only. Phase 3 will add `brands/{bid}/reviews/{id}`.

## Setup

### 1. Accounts you need

1. **Firebase project** (console.firebase.google.com). Upgrade it to the **Blaze** pay-as-you-go plan, which Cloud Functions and Vertex AI require.
2. In the same Google Cloud project, **enable the Vertex AI API**:
   `gcloud services enable aiplatform.googleapis.com --project YOUR_PROJECT_ID`
3. **Anthropic API key** from platform.claude.com.

### 2. Backend

```bash
npm install -g firebase-tools
firebase login
```

Edit `.firebaserc` and put your project id in place of `YOUR_FIREBASE_PROJECT_ID`. Then:

```bash
cd functions && npm install && npm test
```

```bash
firebase functions:secrets:set ANTHROPIC_API_KEY
```

```bash
firebase deploy --only functions,firestore,storage
```

In the Firebase console:
- Enable **Authentication → Email/Password**.
- Create the **Firestore** database and the **Storage** bucket.

When you first deploy `storage.rules`, the CLI asks for permission for Storage rules to read Firestore. Say yes: the membership checks depend on it.

Give the functions' service account permission to call Imagen:

```bash
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:$(gcloud projects describe YOUR_PROJECT_ID --format='value(projectNumber)')-compute@developer.gserviceaccount.com" \
  --role="roles/aiplatform.user"
```

### 3. App

Install Flutter 3.50 or later. Then:

```bash
cd app
dart pub global activate flutterfire_cli
flutterfire configure --project=YOUR_PROJECT_ID
flutter run
```

`flutterfire configure` replaces the placeholder `lib/firebase_options.dart` with your project's real keys. To try the app in a browser, use `flutter run -d chrome`. For Windows and macOS desktop, use `flutter run -d windows` or `flutter run -d macos`.

### Local development with emulators

```bash
echo "ANTHROPIC_API_KEY=sk-ant-..." > functions/.secret.local
```

```bash
cd functions && npm run serve
```

Then point the app at the emulators (`useAuthEmulator`, `useFirestoreEmulator`, `useStorageEmulator`, `useFunctionsEmulator`) while developing.

## Costs (approximate)

| Item | Cost |
|---|---|
| Post ideas (Claude Opus 5.5, ~6 ideas per request) | a few US cents per request |
| Imagen image | about US$0.04 per image (check current Vertex AI pricing) |
| Firebase (Auth, Firestore, Storage, Functions) | free tier covers early usage |

Plan limits are in `functions/src/lib/types.ts` (`PLAN_LIMITS`). Free is 15 images per month.

## Testing status

- `functions`: unit tests for color extraction, text wrapping and every layout and format (`npm test`).
- An end-to-end run against the Firebase emulators passed these checks: sign-up, workspace creation, brand edits, access denied to other users, clients blocked from writing AI output, usage or plan, the free-plan brand limit, and input validation.
- **Not yet verified:** the Storage membership rule. It uses a cross-service lookup into Firestore, and the sandbox that built this code couldn't run that lookup in the emulator. Run the logo-upload step once against your real project to confirm it.
- **Not yet run:** real calls to Claude and Imagen. They need your API key and Google Cloud project.

## Roadmap

**Phase 2: publishing**
- Connect Instagram (Instagram Login), Facebook Pages (Facebook Login) and Google Business Profile (Google OAuth, `business.manage` scope).
- Store tokens encrypted (Secret Manager or KMS) and refresh them on a schedule.
- Publish now or on a schedule (Cloud Tasks).

**Phase 3: reviews**
- Receive Google Business Profile notifications (`NEW_REVIEW`) through Pub/Sub, with a polling backup.
- Claude drafts a reply in the brand's tone, with privacy-safe rules for healthcare, legal and finance.
- Push notification (FCM) → approve or edit → `reviews.updateReply`.

**Phase 4: business**
- Team invites and roles.
- Subscriptions: RevenueCat for iOS and Android in-app purchases; Stripe or Razorpay on web and desktop.
- Admin dashboard.

**Start these approvals now:**
- Meta Business Verification and App Review.
- Google Business Profile API access request.
- Google OAuth verification.
- A D-U-N-S number for the Apple and Google Play developer accounts.
