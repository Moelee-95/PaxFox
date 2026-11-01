# PaxFox: read this first

Implementation snapshot: **2026-11-01**, source baseline **`eb4d9cf`** with local updates. This is the short handoff, not the original requirements document.

## What the app is

Flutter/Dart Material 3 personal finance app, one setup currency (EUR/USD/GBP/IQD), local SQLite, no login or sync. Manual bookkeeping works offline. Document extraction sends selected images/PDFs and categories for the chosen expense/income mode to Gemini. Application version: `1.0.0+1`; Dart SDK constraint: `^3.13.3`; SQLite schema: **13**.

The displayed app name is **PaxFox**, including onboarding, Home, More/About, help text, Android/iOS app labels and `paxfox_...csv` exports. The internal Dart package `moneva`, platform application IDs and `moneva.sqlite` filename remain compatible with existing installations and data. The bundled font alias is `PaxFoxRoboto`.

Android legacy/adaptive and iOS launcher icons use the supplied fox artwork; the original and reproducible generator are `assets/branding/app_icon_source.png` and `tool/generate_app_icons.dart` (see the build section in APP_MAP).

## Screen map

```text
Startup -> open/migrate storage -> failure/retry OR required first-run setup
Setup: currency + cash -> banks/no-bank -> review + optional debts -> main shell
Main bottom tabs: Home | Overview | Cashflow | More (three-dot icon; Back twice within 2 seconds to exit)
  Home: month pager + three tabs: Expenses/refunds | Income | compact info icon (Monthly overview); header amounts omit fractional units; normal tab taps and horizontal swipes; swipe left from the info tab to continue to main Overview
  Monthly overview category cards -> inline matching expenses/refunds; on-screen/system Back returns to categories (system Back clears active selection first); editing and bulk selection
  Overview: prominent wealth/spendable totals + compact editable account cards + compact highlighted debts + interactive monthly net-savings chart (FL Chart; six months with permanent amount labels)
  Cashflow: empty placeholder for future functionality
  Transactions: all-date search + type filter
More: editable local user card + searchable All transactions, Categories, Accounts, Recurring, CSV, Settings cards; Home is only in bottom navigation
  Support: Help & FAQ, Rate App, Changelog, Privacy Policy, Terms and Conditions, About (actions deferred)
  All transactions replaces content; app-bar/system Back restores More
  Management screens push routes; transaction, recurring and scanned-item editors use bottom sheets; no side drawer
  Accounts -> AccountForm (unused banks can be deleted); Categories -> full-page add/edit, 21 color swatches + searchable grouped icons (including brands), pinned Save and header check
  Recurring -> RecurringForm bottom sheet; unpaid history -> retry/skip
  CSV -> multi-select account cards and type bottom sheet; one nine-column file preserves mixed assignments and transfers; legacy five-column imports require one account/type
Floating + stays unchanged -> white modal backdrop with Expense left / Income right; each has Add manually / Scan / Upload file; close stays at + position
  Manual -> TransactionForm bottom sheet with colored category/type and amount header, preselected type and pinned Save
  Scan/upload -> camera, images or PDF -> preparation -> Extract -> expense/income review
  Review -> item edit bottom sheets -> atomic save -> matching Home expense/income tab
Existing entry -> TransactionForm bottom sheet, except legacy single-expense receipts -> invoice review
Long-press entries -> bulk category/account/delete actions
Transaction rows: rounded cards with the description in bold, saved category-color icon circle, visible localized Added on timestamp below and a separately labeled transaction date; no category-name heading or creation-time info button. Slightly larger 34px badges, 20px glyphs and 16px headings/prices. Expense price red with minus, income/refund green with plus, transfer blue without income/expense sign. Home expense/income tabs stay separate.
```

## Architecture and invariants

- `lib/main.dart` owns startup; `core/presentation/app_theme.dart` owns Google-style blue Material 3 light/dark themes and bundled offline Roboto. `screens/main_screen.dart` owns navigation, lifecycle checks and selection. Navigation uses `MaterialPageRoute`, not named URLs.
- Main destinations and Home's inner tabs mount lazily and retain their controllers/scroll position. Cached page widgets listen to store/view changes independently of shell navigation; inactive main pages have tickers disabled. More search also survives tab changes. More, account/debt lists and monthly category reports build rows lazily.
- `core/data/ledger_store.dart` is the injected `ChangeNotifier`, public data/write boundary. Commits reload a complete read-only snapshot. If that reload fails, `StoreStatus` offers a reload and blocks stale interactions without repeating the committed write. Failed reads retain the last complete snapshot.
- The optional local profile uses `profile_name` and `profile_email` in existing settings (no schema bump); `saveProfile` saves both atomically. It is not a login and is not sent for invoice extraction. More's support options are visual placeholders by user request; no support actions, authentication or logout are implemented.
- Category sheets share lazy saved-color/icon grids, contextual type switching and add actions; Edit opens Categories on the matching kind, then Back returns to the picker. Categories uses lazy rounded cards, numbered badges and an app-bar add button. Manual forms allow expense/income/refund/transfer; recurring is expense/income only; scan-review/item-review forms and bulk category changes retain their financial type. Type-only fields use a shared single/multi-select sheet (CSV preserves multi-selection). `EntryEditorSheet` shares keyboard-aware layout, pinned Save and protected pending writes. Category renames are handed back to drafts by stable category ID.
- Categories store stable icon IDs and an optional opaque ARGB color. Schema 13 adds nullable `categories.color`; transaction rows use saved color for the icon badge and a neutral fallback when unset. Price color/sign reflects transaction type independently. CategoryForm supports expense/income selection for new categories; existing kind stays fixed. Custom colors appear in category lists, transaction badges, manual category options and monthly reports. The catalog retains 92 original icons and adds 21 icons (including Font Awesome brands); assets are bundled for offline use.
- `core/data/ledger_database.dart` owns schema/migrations; `core/domain/` owns money and schedules. UI components live in `core/presentation/`; invoice code in `features/receipts/`.
- UI amounts use comma thousands grouping (1,234.56), including editable money fields; CSV/extraction serialization stays ungrouped.
- Money is **integer minor units** (2 decimals for EUR/USD/GBP, 3 for IQD), never floating-point. Transactions store positive magnitudes; type determines sign. Refunds reduce spending; transfers affect accounts only. New writes use the setup currency; other-currency rows remain stored and excluded. Upgrades default to EUR without relabeling old amounts.
- Balances derive from opening balance + eligible transactions. Cash cannot overdraw; banks require their own overdraft permission. Blocked accounts can receive funds but cannot fund expenses/outgoing transfers. Preserve historical/future balance validation and atomic rollback.
- Transaction date and UTC creation timestamp are separate; edits preserve creation time. Account opening-date inclusion has legacy semantics that must survive migration.
- Recurring income/expense posting is idempotent. Recurring asset/liability switches are **metadata only**. Outstanding debts are separate liabilities subtracted from account wealth, without changing spending balances.
- Expense review saves one transaction per nonzero item, negative items as refunds, with no extra total transaction. Income mode uses income categories, one payslip net payment, and statement income credits only (no expenses, own-account transfers, balances or unpaid invoices); every saved income item must be positive. Mode is persisted as `entry_type` inside existing batch draft JSON (legacy absence means expense), with no schema change. Total comes from reviewed items. Currency confirmation appears only for missing/mismatched extraction. Every reviewed item has its own editable invoice date; multiple-invoice extraction must supply each date. Oversized photos are downsampled natively, then compressed once and reused; preparation has cancellation and a 45-second per-page limit.
- Shared `AsyncAction` handles duplicate-submit protection and retryable saves for transactions, accounts, debts, categories, recurring forms and settings. Gemini has an end-to-end deadline, safe connection/service error messages, cancellation and retained images for retry; request encoding runs in an isolate. Preview widgets cache path resolution and decode at display height; progress ticks rebuild only their text. Monthly category rows and rankings are indexed per snapshot.
- Ledger search text is normalized on the first text search, not on every snapshot reload; type-only filters cache one result per type/snapshot. Category lookup is indexed, and icon/color-only edits skip label-renaming writes. Financial calculations and complete-snapshot recovery remain unchanged.
- Snapshot refresh prepares populated month reports/rankings and today's balances before publishing. Transaction decoding/preparation uses a worker at 1,000+ rows; small snapshots stay inline. The month pager commits after settling (180ms chevrons, accumulated rapid taps). A separate refresh notifier drives a global spinner without rebuilding retained pages; save controls share `BusyLabel`. CSV export encoding/filtering/sorting uses a worker. See PERFORMANCE for measurements and loading/memory tradeoffs.
- Home defers child updates on hidden inner tabs until a tap/drag needs them, avoiding unused transaction-list layout on month changes. Home lists retain an 80px prebuild buffer. Main destinations still receive hidden-page store updates.

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

Validation on 2026-11-01 after split creation menu and income documents: **197 passing tests**, clean analyzer and successful release APK. New coverage checks income parsing/filtering, PDF MIME/bytes and cleanup, positive income validation, blocked receiving accounts, source edit/delete, manual Income routing, and two-column menu accessibility at 320px/1.8x text. Native file/camera providers and live Gemini classification remain unverified.

Validation on 2026-11-01 after month navigation/loading improvements: **203 passing tests** with `CAPTURE_UI=true`, clean analyzer and successful release APK with the unchanged production package ID. Coverage includes rapid month taps/swipes/year changes, hidden-tab row deferral/freshness, prepared/lazy report equivalence, loading feedback without retained-content rebuilds, and financial/recovery regressions. On the connected SM-S916B/60Hz with 24,000 synthetic entries, final build p95 was 14.905ms for transaction month changes, 8.957ms for report changes and 1.532ms for warmed main navigation; some transaction frames still exceeded the frame budget. The separate in-memory benchmark package was removed afterward. See PERFORMANCE for full results and limits.

Validation on 2026-11-01 after reusable category/type and entry editor sheets: **210 passing tests** with `CAPTURE_UI=true`, clean analyzer and successful release APK. Coverage includes selection cancellation, contextual type restrictions, category creation/renaming, staged CSV type selection, transfer/refund selection, lazy rendering of 250 categories, and keyboard-safe 320px/1.8x text layouts. Rendered expense/income, category grids and dark/keyboard layouts were inspected. No persisted schema or financial rules changed.

Validation on 2026-11-01 after category management cards: **210 passing tests**, clean analyzer and successful release APK. Picker Edit opens the matching Categories tab; return/rename retention, lazy management rows, light/dark cards and narrow large-text layouts were verified. No data schema or financial rules changed.

Brand theme validation on 2026-11-01: the 210-test regression run passed 209 tests with one obsolete hardcoded blue-color expectation. After updating that expectation, all 7 focused theme/recurring tests passed (including 2 new light/dark contrast tests). Analyzer and release APK build passed. Rendered More/editor/category screens were checked in light/dark and narrow large-text layouts. No navigation, data or financial rules changed.

Outline theme validation on 2026-11-01: **213 tests passed**, followed by 14 focused theme/sheet/More tests after the final icon-style adjustment; analyzer and release build passed. Orange fills were replaced with neutral surfaces and orange borders for primary buttons/FABs. Installed release was checked with 20 More-to-Cashflow swipe cycles and a responsive return Home; no new ANR. The reported original debug ANR was symbolized as a debugger pause on an exception; exact Dart exception remains unknown. See PERFORMANCE.

Theme rollback on 2026-11-01: restored the original blue/neutral light and dark themes, standard buttons/navigation, multicolor More options and purple sheet actions at the user's request. Brand/orange theme experiments above are historical and no longer apply. Navigation regression coverage is retained.

Monthly savings validation on 2026-11-01: **216 tests passed** with `CAPTURE_UI=true`, clean analyzer and successful release APK (64.6MB). New coverage checks net/refund/transfer/currency rules, real bar taps, month/year paging, zero data, refreshed snapshots and dark 320px/1.8x IQD layouts. Light/dark previews inspected. Release installed preserving data; on-device chart visual inspection was unavailable because the screen was off. No schema change.

Six-month chart revision on 2026-11-01: all six months remain visible at narrow widths and large text, with permanent compact amount labels on every bar, including zero/negative values. Exact currency values remain available in the selected summary/tooltips. Six focused chart/navigation tests pass; analyzer and release build pass. Light/dark narrow previews inspected. The updated APK has not been installed because no Android device was connected at completion.

Camera and live Gemini remain unverified. iOS and production signing/publishing were not verified; release currently uses the existing debug signing key. Support actions remain deferred. No full backup/restore, web support, bank integration or cloud sync exists.

Suggested future prompt: **“Read AI_CONTEXT.md first. Use its linked maps only as needed, inspect the files relevant to my request, and preserve the documented financial invariants.”**
