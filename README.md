# Super Mom

A weekday routine app for Muslim families. Kids tick off their jobs (salah, homework, chores, healthy eating, screen time, Qur'an) on their own device; Mom sees every tick live on her phone and can change anything, give time-outs, and set the rewards kids earn with their stars.

- `super-mom-prototype.html` – clickable design prototype
- `app/` – the Flutter app (Android, iOS, web)
- `firebase/firestore.rules` – the security rules (what each phone is allowed to do)
- `firebase/rules-tests/` – tests that try to break the rules
- `firebase/functions/` – optional: push notification to Mom when a child ticks a task

## Stages

| Stage | What | Status |
|---|---|---|
| 1 | Core app: Mom and Kid modes, several kids with themes, routine with time windows, kids tick / Mom edits, stars, time-outs, rewards, Monday reset, prayer times by city, daily reminder, Qur'an tracker, sunnah fast bonus | Done |
| 2 | Cloud: parent sign-in (Google, Apple, email), QR linking of each child's device, live sync, server-side security rules, prayer-time reminders, push notifications to Mom | **Done** (needs your Firebase project to go live) |
| 3 | School: Google Classroom import, competition reminders | Next |
| 4 | Testing, privacy policy, Google Play and App Store release | Needs your developer accounts |

## How it works

**Mom's phone.** Mom signs in (Google, Apple or email) and creates the family. She sees the parent screens. "Kids mode" hands the phone to the children; the parent PIN gets her back.

**A child's phone or tablet.** Choose "This is my child's device" and scan the QR code from Mom's phone (Settings → Children's devices → Link a device), or type the 8-letter code. The device signs in anonymously; the child never has an account or password. A device linked to one child opens straight to that child's page; a shared tablet shows "Who are you?".

**What the server enforces** (`firebase/firestore.rules`, tested in `firebase/rules-tests`):
- A child's device sees only the children it is linked to.
- It can only tick or untick that child's tasks, today, while the task's time window is open (60 minutes grace for slow networks). Salah tasks follow the prayer times, which Mom's phone writes ahead for 5 weeks.
- It cannot undo Mom's ticks, remove time-outs, change last week, edit the routine, rewards or settings, or give itself more children.
- Link codes work once, expire after 10 minutes, and cannot be listed or guessed in bulk.
- Mom can remove a device at any time; it loses access immediately.

**The week** is named after its Monday. Stars stay visible over the weekend; on Monday Mom's phone saves a one-line summary per child and deletes last week's ticks.

## Rules for stars

- 90% of a day's tasks done = 2 stars, 60% = 1 star. Five school days = 10 stars.
- Each time-out = −1 star. A done bonus task (e.g. sunnah fast) = +1 star. Maximum 10.

## Connect your Firebase project (needed before installing on phones)

1. Go to https://console.firebase.google.com, create a project (e.g. "super-mom"). Analytics is not needed.
2. **Authentication** → Sign-in method → enable **Google**, **Apple**, **Email/Password** and **Anonymous** (children's devices use Anonymous).
3. **Firestore Database** → Create database (production mode, a region near you).
4. On your computer, with Flutter installed:
   ```
   npm install -g firebase-tools
   dart pub global activate flutterfire_cli
   firebase login
   cd app
   flutterfire configure        # pick your project, Android + iOS; replaces lib/firebase_options.dart
   cd ..
   firebase use --add           # pick your project
   firebase deploy --only firestore:rules
   ```
5. Optional, for "Aisha ticked a task" notifications on Mom's phone: upgrade the project to the **Blaze** plan (pay as you go; a family stays inside the free allowance, but Google asks for a card), then `cd firebase/functions && npm install && cd ../.. && firebase deploy --only functions`. On iPhone this also needs an APNs key uploaded in Firebase → Project settings → Cloud Messaging.
6. iPhone only, in Xcode (`app/ios/Runner.xcworkspace`) → Signing & Capabilities: add **Sign in with Apple** and **Push Notifications**. For Google sign-in on iPhone, add the `REVERSED_CLIENT_ID` from `GoogleService-Info.plist` as a URL scheme.

**Adhan sound.** Reminders use the normal notification sound. To play an adhan, add a recording you have the rights to as `app/android/app/src/main/res/raw/adhan.mp3` and `app/ios/Runner/adhan.caf` (30 seconds at most on iPhone) and build with `--dart-define=ADHAN_SOUND=true`.

## Run and test

```
cd app
flutter pub get
flutter test                                   # star and time-window rules
flutter run                                    # on a phone, after "Connect your Firebase project"
```

Without a Firebase project, run everything against the local emulator:

```
firebase emulators:start --only auth,firestore --project demo-supermom
cd app && flutter run -d chrome --dart-define=USE_EMULATOR=true
# Android emulator: add --dart-define=EMULATOR_HOST=10.0.2.2
```

Security rules tests: `cd firebase/rules-tests && npm install && npm test`.

Two-device test (Mom + child's tablet in two browsers): build with `flutter build web --dart-define=USE_EMULATOR=true`, serve `app/build/web` on port 8765, start the emulators, then `node app/e2e/two_devices.js` (needs Playwright).

## Known limits

- Prayer times use the phone's own time zone. Set the phones to the family's local time zone.
- Ticks made offline sync when the device is back online; if that is more than 60 minutes after the task closed, the server refuses them and Mom can mark the task done herself.
- A child can choose any reward from the list on their own device; the app only offers the ones their stars allow, and Mom sees the pick.
