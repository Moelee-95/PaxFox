# Paxlee

An offline Flutter personal finance app with local SQLite storage. Start with [AI_CONTEXT.md](AI_CONTEXT.md) for the current implementation, [the screen/source map](docs/APP_MAP.md) to locate code, and [data/workflow contracts](docs/DATA_AND_WORKFLOWS.md) before changing financial behavior.

## Features

- One setup currency: EUR, USD, GBP or IQD; exact integer minor-unit arithmetic, no FX conversion.
- Cash/bank accounts, account-specific overdraft and blocked-funds rules, outstanding debts and required first-run setup.
- Expenses, income, refunds and transfers; edit/delete, monthly browsing, search, type filters and atomic bulk actions.
- Home with separate expense/income tabs and monthly category reports; Overview for account wealth and debts; Cashflow reserved for future work.
- More with a local profile, searchable management options, CSV import/export and settings. Support options are visible with actions deferred.
- Category editor with 21 colors and 113 searchable grouped icons, including bundled brands. Transaction badges use saved category colors; prices show transaction direction independently.
- Monthly recurring expense/income schedules, catch-up on startup/resume, pause/resume, unpaid history and explicit retry/skip. These are bookkeeping entries, not real bank payments.
- Invoice capture/gallery, native image preparation, Gemini extraction and editable review with an independent date per item. Saving creates individual expenses/refunds atomically and retains shared source images.
- Material 3 light/dark themes, bundled offline fonts and compact responsive rows.

## Run and verify

Requires Flutter compatible with Dart 3.13.3+ and the Android SDK/JDK. Dependencies are pinned in `pubspec.lock`.

```sh
flutter pub get
flutter analyze
flutter test --concurrency=2
flutter run
flutter build apk --release
```

Android requires API 24+. The release APK is `build/app/outputs/flutter-apk/app-release.apk`. Android application ID `de.alhayali.moneva`, Dart package `moneva` and database filename `moneva.sqlite` retain their original values for installation/data compatibility; displayed branding is Paxlee. Release currently uses the existing debug signing key; production signing is separate.

Only Android/iOS platform scaffolds are present. iOS targets 15.0 and requires macOS/Xcode and device/signing verification. The data layer supports Windows/Linux SQLite FFI, but desktop platform scaffolds are not supplied. Web is not supported.

## Code ownership

| Area | Location |
| --- | --- |
| Startup and storage recovery | `lib/main.dart`, `lib/core/presentation/store_status.dart` |
| Money, balances, query indexes, categories and recurrence | `lib/core/domain/` |
| Validated writes, complete snapshots, SQLite migrations and CSV codec | `lib/core/data/` |
| Navigation, forms and feature screens | `lib/screens/` |
| Shared visual components and async actions | `lib/core/presentation/` |
| Capture, image preparation, Gemini and invoice review | `lib/features/receipts/` |

`LedgerStore` is injected through constructors. Writes validate and commit atomically, then publish a complete read-only snapshot. Failed reloads retain the previous snapshot and expose read-only recovery without repeating a committed write. Screens retain visited page state and use scoped listeners; long lists build visible rows lazily. See [performance notes](docs/PERFORMANCE.md) for implementation details, reproducible benchmarks and limits.

## Data and invoice extraction

Data lives in the platform application-support directory. There is no login, sync, analytics backend or bank integration. Tapping Extract sends selected images and expense category names to Gemini; the local profile is not included. Receipt copies remain private to the app. CSV exports combine multiple accounts and all transaction types using nine columns, including both accounts for transfers; old five-column files remain importable with one selected account/type. Account names must match existing app accounts. CSV is not a full backup. Full backup/restore and orphan-image sweeping are not implemented.

Invoice extraction uses the encrypted remote configuration protocol in `gemini_key_provider.dart` and the injectable `InvoiceExtractor` contract. The default model is `gemini-3.5-flash-lite`; override with `--dart-define=GEMINI_MODEL=your-enabled-model`. Bundled config decryption material is obfuscation, not server-side key protection. Timeout is configurable in More > Settings, from 30 to 900 seconds (default 180). Automated tests use mock services and synthetic records, without paid API requests or private financial fixtures.

## Validation

On 2026-11-01: clean analyzer, 190 passing tests, successful release APK and checked rendered light/dark and narrow/large-text layouts. Tests cover financial policies, migrations, recurrence, invoice handling, failure recovery, editing/selection, navigation, page-state retention and rebuild regressions.

Real-device frame times, live Gemini, native camera behavior, iOS and production publishing remain unverified. Use profile/release mode on a physical device to assess smoothness; see [performance notes](docs/PERFORMANCE.md).
