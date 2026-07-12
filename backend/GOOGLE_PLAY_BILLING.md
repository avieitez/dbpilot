# Google Play Billing setup

The backend verifies every Pro entitlement against Google Play. Never add a
service-account JSON file to this repository.

## 1. Google Play Console

1. Create subscriptions with product IDs `dbpilot_pro_monthly` and
   `dbpilot_pro_yearly`.
2. Add and activate their base plans:
   - `dbpilot_pro_monthly`: 3,99 € / month.
   - `dbpilot_pro_yearly`: 39,99 € / year.
3. Upload a signed AAB using package name `com.avieitez.dbpilot` to an internal
   testing track.
4. Add the test Google accounts as license testers and internal testers.

## 2. Google Cloud and Play API

1. Enable **Google Play Android Developer API** in the Google Cloud project
   linked to Play Console.
2. Create a service account for the DBPilot backend.
3. In Play Console, grant that service account access to the DBPilot app and
   permission to view subscriptions and manage orders/subscriptions.

## 3. Firebase

1. Enable Cloud Firestore in Native mode for project `dbpilot-feb6e`.
2. The backend service account must be allowed to use Firebase Authentication
   and read/write Firestore.
3. Client access to `users/*/subscriptions/*` and `play_purchase_tokens/*`
   should remain denied by Firestore Security Rules. Only Firebase Admin uses
   these collections.

## 4. Render environment variables

Configure the variables shown in `.env.example`:

- `FIREBASE_PROJECT_ID`
- `FIREBASE_SERVICE_ACCOUNT_JSON`
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`
- `GOOGLE_PLAY_PACKAGE_NAME`
- `GOOGLE_PLAY_PRO_PRODUCT_IDS`

The two JSON variables may contain the same service account when that account
has both Firebase and Play permissions. Preserve escaped `\n` characters in
the private key.

## 5. End-to-end test

1. Deploy the backend.
2. Install DBPilot from the internal Play testing track. Sideloaded debug APKs
   cannot reliably test Play subscriptions.
3. Sign in with a Firebase/Google account that is also a Play license tester.
4. Purchase Pro from the Paywall.
5. Confirm `GET /api/v1/subscriptions/me` returns `{"plan":"pro"}` when called
   with that user's Firebase ID token.

The app revalidates the subscription when it starts and immediately after a
purchase or restore. Real-time Developer Notifications can be added later for
server-side updates while the app is closed.
