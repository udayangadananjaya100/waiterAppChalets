# Oruthota Service

An English language Flutter Android app for the Oruthota Chalets restaurant team. The app uses the existing Next.js login and waiter routes plus the existing Supabase project. The admin project is separate and has not been edited.

## For the first waiter

1. Open **Oruthota Service**. The first screen offers a **Practice shift** with realistic sample tables and menu items. Practice never sends data to Supabase.
2. Open **Connection settings** from the login screen. Enter the HTTPS address of the deployed admin website. The Supabase URL and publishable key from the supplied admin project are prefilled under Advanced connection. Confirm them with your team if you deploy against another project.
3. Sign in with the same email or employee number and password as the admin web app. Choose a table, add menu items, review the draft and send it. Kitchen status appears in the live order. Mark prepared dishes as served and send the bill to the cashier. Only the cashier settles payment.

The admin website URL is not present in the source repository. It must be entered once on the device or supplied at build time with `--dart-define=API_BASE_URL=https://admin.example.com`. A waiter account is needed to test live sign-in and order writes. Do not put a service role key in the app.

## Features

- First-use guide, searchable tables and menu, section and ownership filters.
- Separate draft review before sending, stock and batch selection, price and stock recheck, guest mobile field.
- Live order and kitchen state, served quantity, guest check-in QR linking, cashier handoff and confirmed bill preview.
- Table ownership handling, waiter release, secure cookie storage, foreground refresh, offline state and review after an uncertain write.
- Offline Practice shift for staff training.

The app intentionally does not edit sent items or take payment. The existing server does not expose a safe, atomic API for those operations; changes to a sent item are handed to the cashier to keep kitchen and stock records consistent. The server's `add-to-order` operation is not idempotent. After a lost response, the app blocks retries for that table until the waiter compares the live order and clears the draft. If the server partially applies an order, the cashier must reconcile stock and totals.

## Build

Flutter 3.47.5, Dart 3.13.4 and JDK 17 were used. Android SDK 35/36 is available on the build machine. If `.tools/flutter` and `.tools/java` are present, run from PowerShell:

```powershell
cd 'G:\OruthotaChaletsAdmin-main (1)\Flutter App'
.\scripts\build-android.ps1
```

The script maps a short temporary drive letter so Flutter and Gradle can work with the parentheses in the folder name, and sets a short Java temporary path. It produces `build/app/outputs/flutter-apk/app-debug.apk`. This is a QA install build. For an app distributed to staff, configure a company upload keystore using `android/key.properties.example`, then run `build-android.ps1 -Release`. Keep the keystore and `key.properties` private.

To run checks:

```powershell
flutter analyze
flutter test
```

Six screen captures from the practice workflow are in `test/screenshots`. Update them intentionally with `flutter test --dart-define=SCREENSHOTS=true --update-goldens` after UI changes. The same tests work without the screenshot flag as interaction tests.

## Backend notes

The admin project's `docs/waiter-mobile-app-reference.md` proposes a Bearer token change. This app instead reuses the existing `auth_token` cookie returned by `/api/auth/login`; it stores that cookie in Android encrypted storage and sends it to the existing Next.js routes. Supabase REST uses the project's publishable key, never a secret key. Direct table reads and updates match the web waiter's existing Supabase operations. The current live Supabase project responded to read-only requests for the waiter tables on 25 September 2026. A live write and Android device login still need testing with the deployed admin URL and a waiter account.

The server route `/api/waiter/add-to-order` uses a single Restaurant warehouse, merges rows by menu item and price, and may partially apply a failed request. The app limits linked stock to that warehouse and blocks sending the same dish from different batches at the same price. Stock and order mutations remain subject to the server's existing business rules and policies.
