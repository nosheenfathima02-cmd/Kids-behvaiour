# Launch checklist (Stage 4)

Everything in the app needed for the stores is ready: icon, account deletion, privacy policy, store text, screenshots and release signing. What is left needs your accounts. Steps marked **you** need you; **together** means send me what you see and I do the rest.

## Timeline

| Week | What | Who |
|---|---|---|
| 1 | Firebase project, Google Play account, website on, first test build on your phones | you, then together |
| 1–3 | Google Play **closed test**: at least 12 testers for 14 days in a row (required for new personal developer accounts) | you invite, together fix |
| 2–3 | Apple developer account, TestFlight on iPhone | you, then together |
| 3–4 | Submit for review: Google Play (usually 1–7 days), App Store (usually 1–3 days) | together |
| later | Google Classroom: Google verifies the Classroom scopes (a few weeks), then a small update switches it on | together |

## 1. Before anything else

- [ ] **Contact email.** Choose the support email shown to parents and stores, and replace `[CONTACT EMAIL]` in `docs/privacy.html` and `docs/index.html` (or tell me and I will).
- [ ] **Name check.** Search Google Play and the App Store for "Super Mom". If an app with that name exists, pick one of the alternatives at the end of `store/store-listing.md`.
- [ ] **App ID.** The Android ID is `com.supermom.super_mom` and can never change after the first upload. Tell me now if you want a different one (for example your own domain backwards, like `com.yourname.supermom`). The iPhone bundle ID should match.

## 2. Website (privacy policy and support page) — you, 2 minutes

GitHub → the `kids-behvaiour` repository → **Settings → Pages** → Source: *Deploy from a branch*, Branch: `main`, Folder: `/docs` → Save. After a minute the pages are at:

- https://nosheenfathima02-cmd.github.io/kids-behvaiour/
- https://nosheenfathima02-cmd.github.io/kids-behvaiour/privacy.html

## 3. Firebase — you, then together

Follow "Connect your Firebase project" in the README (create the project, turn on sign-in methods and Firestore, run `flutterfire configure`, deploy the rules). For the store build, turn on **App Check** with Play Integrity (Android) and App Attest (iPhone) so only the real app can reach your data.

## 4. Android release

1. **Create the upload key** (once, on your computer; keep the file and passwords safe and never put them on GitHub):
   ```
   keytool -genkey -v -keystore ~/supermom-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Create `app/android/key.properties` (already ignored by git):
   ```
   storePassword=<password>
   keyPassword=<password>
   keyAlias=upload
   storeFile=/full/path/to/supermom-upload.jks
   ```
3. Build the store bundle, with Google Classroom hidden until Google has verified it:
   ```
   cd app
   flutter build appbundle --release --dart-define=CLASSROOM=false
   ```
   The file is `app/build/app/outputs/bundle/release/app-release.aab`.
4. **Google Play Console** (you: https://play.google.com/console, $25 once, identity check can take a few days):
   - Create app → name, default language English, App, Free.
   - **Testing → Closed testing**: upload the `.aab`, add at least 12 testers by email (family and friends with Android phones), and keep the test running for 14 days. They must opt in from the link Google gives you.
   - **Policy → App content**: privacy policy URL, ads (none), app access (give the demo account), target audience (6–8, 9–12, 18+), content rating, data safety. All answers are in `store/store-listing.md`.
   - **Account deletion URL**: `https://nosheenfathima02-cmd.github.io/kids-behvaiour/#delete`
   - **Main store listing**: text from `store/store-listing.md`, icon `store/graphics/icon-512.png`, feature graphic `store/graphics/feature-graphic.png`, phone screenshots `store/screenshots/play/`.
   - After 14 days: apply for production access, then send the release for review.

## 5. iPhone release

Building for iPhone needs a Mac with Xcode (or a cloud Mac service such as Codemagic).

1. **Apple Developer Program** (you: https://developer.apple.com/programs/, $99 per year).
2. In Xcode open `app/ios/Runner.xcworkspace` → Runner → Signing & Capabilities: choose your team, set the bundle ID, add **Sign in with Apple** and **Push Notifications**.
3. `flutter build ipa --release --dart-define=CLASSROOM=false`, then upload with Xcode or Transporter.
4. **App Store Connect**: create the app, fill in the text, privacy answers and review notes from `store/store-listing.md`, screenshots from `store/screenshots/ios/`, then test with **TestFlight** before submitting.

## 6. Demo account for the reviewers — together

Both stores need a working sign-in. Create a parent account (email + password) in the released app, add one child, set the PIN to 1234, and put the email and password in the review notes.

## 7. Google Classroom verification (after launch) — together

Classroom uses "sensitive" Google permissions, so Google must verify the app before the public can use it:
- Google Cloud console → OAuth consent screen: app name, logo, support email, the privacy policy URL, and the two Classroom scopes.
- Verify the website domain in Google Search Console.
- Record a short screen video of the Classroom import on a phone (Google asks for it).
- When approved, release an update built without `--dart-define=CLASSROOM=false`.

Until then, add your own children's school accounts as test users to use Classroom yourself.

## Store images

Regenerate after app changes (needs the emulators and the web build, see the README):
```
OUT=/tmp/demo.json flutter test app/tool/demo_family_test.dart   # run inside app/
node store/screenshots.js /tmp/demo.json play /tmp/raw-play
node store/screenshots.js /tmp/demo.json ios /tmp/raw-ios
python3 store/compose.py /tmp/raw-play /tmp/raw-ios
python3 store/check_listing.py
```
