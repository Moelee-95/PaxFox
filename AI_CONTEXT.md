# Paxlee: read this first

Implementation snapshot: **2026-11-01**, source baseline **`eb4d9cf`** with local updates. This is the short handoff, not the original requirements document.

## What the app is

Flutter/Dart Material 3 personal finance app, one setup currency (EUR/USD/GBP/IQD), local SQLite, no login or sync. Manual bookkeeping works offline. Invoice extraction sends selected images and expense categories to Gemini. Application version: `1.0.0+1`; Dart SDK constraint: `^3.13.3`; SQLite schema: **13**.

The displayed app name is **Paxlee**, including onboarding, Home, More/About, help text, Android/iOS app labels and `paxlee_...csv` exports. The internal Dart package `moneva`, platform application IDs and `moneva.sqlite` filename remain compatible with existing installations and data. The bundled font alias is `PaxleeRoboto`.

## Screen map

```text
Startup -> open/migrate storage -> failure/retry OR required first-run setup
Setup: currency + cash -> banks/no-bank -> review + optional debts -> main shell
Main bottom tabs: Home | Overview | Cashflow | More (three-dot icon; Back twice within 2 seconds to exit)
  Home: month pager + three tabs: Expenses/refunds | Income | compact info icon (Monthly overview); header amounts omit fractional units; normal tab taps and horizontal swipes; swipe left from the info tab to continue to main Overview
  Monthly overview category cards -> inline matching expenses/refunds; on-screen/system Back returns to categories (system Back clears active selection first); editing and bulk selection
  Overview: prominent wealth/spendable totals + compact editable account cards + compact highlighted debts
  Cashflow: empty placeholder for future functionality
  Transactions: all-date search + type filter
More: editable local user card + searchable Home, All transactions, Categories, Accounts, Recurring, CSV, Settings cards
  Support: Help & FAQ, Rate App, Changelog, Privacy Policy, Terms and Conditions, About (actions deferred)
  All transactions replaces content; app-bar/system Back restores More
  Management screens push routes; Back returns to More; no side drawer
  Accounts -> AccountForm (unused banks can be deleted); Categories -> full-page add/edit, 21 color swatches + searchable grouped icons (including brands), pinned Save and header check
  Recurring -> RecurringForm; unpaid history -> retry/skip
  CSV -> multi-select account/type cards; one nine-column file preserves mixed assignments and transfers; legacy five-column imports require one account/type
Floating + -> white modal backdrop + Add manually / Scan invoice / From gallery / close
  Manual -> TransactionForm
  Scan -> capture/gallery -> image optimization -> Extract -> invoice review
  Review -> item edit dialogs -> atomic save -> main Home
Existing entry -> TransactionForm, except legacy single-expense receipts -> invoice review
Long-press entries -> bulk category/account/delete actions
Transaction rows: rounded cards with the description in bold, saved category-color icon circle, visible localized Added on timestamp below and a separately labeled transaction date; no category-name heading or creation-time info button. Slightly larger 34px badges, 20px glyphs and 16px headings/prices. Expense price red with minus, income/refund green with plus, transfer blue without income/expense sign. Home expense/income tabs stay separate.
```

## Architecture and invariants

- `lib/main.dart` owns startup; `core/presentation/app_theme.dart` owns Google-style blue Material 3 light/dark themes and bundled offline Roboto. `screens/main_screen.dart` owns navigation, lifecycle checks and selection. Navigation uses `MaterialPageRoute`, not named URLs.
- Main destinations and Home's inner tabs mount lazily and retain their controllers/scroll position. Cached page widgets listen to store/view changes independently of shell navigation; inactive main pages have tickers disabled. More search also survives tab changes. More, account/debt lists and monthly category reports build rows lazily.
- `core/data/ledger_store.dart` is the injected `ChangeNotifier`, public data/write boundary. Commits reload a complete read-only snapshot. If that reload fails, `StoreStatus` offers a reload and blocks stale interactions without repeating the committed write. Failed reads retain the last complete snapshot.
- The optional local profile uses `profile_name` and `profile_email` in existing settings (no schema bump); `saveProfile` saves both atomically. It is not a login and is not sent for invoice extraction. More's support options are visual placeholders by user request; no support actions, authentication or logout are implemented.
- Categories store stable icon IDs and an optional opaque ARGB color. Schema 13 adds nullable `categories.color`; transaction rows use saved color for the icon badge and a neutral fallback when unset. Price color/sign reflects transaction type independently. CategoryForm supports expense/income selection for new categories; existing kind stays fixed. Custom colors appear in category lists, transaction badges, manual category options and monthly reports. The catalog retains 92 original icons and adds 21 icons (including Font Awesome brands); assets are bundled for offline use.
- `core/data/ledger_database.dart` owns schema/migrations; `core/domain/` owns money and schedules. UI components live in `core/presentation/`; invoice code in `features/receipts/`.
- UI amounts use comma thousands grouping (1,234.56), including editable money fields; CSV/extraction serialization stays ungrouped.
- Money is **integer minor units** (2 decimals for EUR/USD/GBP, 3 for IQD), never floating-point. Transactions store positive magnitudes; type determines sign. Refunds reduce spending; transfers affect accounts only. New writes use the setup currency; other-currency rows remain stored and excluded. Upgrades default to EUR without relabeling old amounts.
- Balances derive from opening balance + eligible transactions. Cash cannot overdraw; banks require their own overdraft permission. Blocked accounts can receive funds but cannot fund expenses/outgoing transfers. Preserve historical/future balance validation and atomic rollback.
- Transaction date and UTC creation timestamp are separate; edits preserve creation time. Account opening-date inclusion has legacy semantics that must survive migration.
- Recurring income/expense posting is idempotent. Recurring asset/liability switches are **metadata only**. Outstanding debts are separate liabilities subtracted from account wealth, without changing spending balances.
- Invoice review saves one transaction per nonzero item, negative items as refunds, with no extra total transaction. Total comes from reviewed items. Currency confirmation appears only for missing/mismatched extraction. Every reviewed item has its own editable invoice date; multiple-invoice extraction must supply each date. Oversized photos are downsampled natively, then compressed once and reused; preparation has cancellation and a 45-second per-page limit.
- Shared `AsyncAction` handles duplicate-submit protection and retryable saves for transactions, accounts, debts, categories, recurring forms and settings. Gemini has an end-to-end deadline, safe connection/service error messages, cancellation and retained images for retry; request encoding runs in an isolate. Preview widgets cache path resolution and decode at display height; progress ticks rebuild only their text. Monthly category rows and rankings are indexed per snapshot.
- Ledger search text is normalized on the first text search, not on every snapshot reload; type-only filters cache one result per type/snapshot. Category lookup is indexed, and icon/color-only edits skip label-renaming writes. Financial calculations and complete-snapshot recovery remain unchanged.

## Read only what you need next

| Task | Read |
| --- | --- |
| Understand screens, find an implementation, select tests | [Screen and source map](docs/APP_MAP.md) |
| Change financial behavior, storage, receipts, CSV or recurring | [Data and workflows](docs/DATA_AND_WORKFLOWS.md) |
| Export/build or port to another platform | [Build and porting](docs/APP_MAP.md#build-export-and-porting) |
| Navigation lag, lazy rendering and benchmark evidence | [Performance notes](docs/PERFORMANCE.md) |

The maps cover every `lib/` Dart file. Use their ownership tables to read only affected code/tests. The ignored `Moneva_Codex_Implementation_Prompt.md` contains broader requirements, including unimplemented features; it is not the current feature inventory.

## Verification

```sh
flutter analyze
flutter test --concurrency=2
flutter build apk --release
```

Validation on 2026-10-31 after performance cleanup: **181 passing tests** with two workers and `CAPTURE_UI=true`, clean analyzer and successful release APK (`build/app/outputs/flutter-apk/app-release.apk`). Rendered light/dark and narrow/large-text layouts were checked. Tests cover financial invariants, migrations, read recovery, category appearance-only writes, page retention, hidden-page data updates and navigation rebuild counts. Reproducible synthetic measurements and tradeoffs are in [PERFORMANCE.md](docs/PERFORMANCE.md).

Validation on 2026-11-01 after multi-account/type CSV: **190 passing tests** with two workers and `CAPTURE_UI=true`, clean analyzer and successful release APK. Tests cover mixed account/type round-trips (including transfers and all currency precisions), duplicate skipping, legacy-file assignment, selection filtering, same-day funding, protected earlier deficits and atomic rollback. CSV controls were checked in rendered light/dark and 320px/1.8x text previews. No schema change.

No Android device was connected, so real-device frame times, camera and live Gemini remain unverified. iOS and production signing/publishing were not verified; release currently uses the existing debug signing key. Support actions remain deferred. No full backup/restore, web support, bank integration or cloud sync exists.

Suggested future prompt: **“Read AI_CONTEXT.md first. Use its linked maps only as needed, inspect the files relevant to my request, and preserve the documented financial invariants.”**
