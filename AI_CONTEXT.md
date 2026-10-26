# Moneva: read this first

Implementation snapshot: **2026-10-26**, source baseline **`eb4d9cf`**. This is the short handoff, not the original requirements document.

## What the app is

Flutter/Dart Material 3 personal finance app, one setup currency (EUR/USD/GBP/IQD), local SQLite, no login or sync. Manual bookkeeping works offline. Invoice extraction sends selected images and expense categories to Gemini. Application version: `1.0.0+1`; Dart SDK constraint: `^3.13.3`; SQLite schema: **12**.

## Screen map

```text
Startup -> open/migrate storage -> failure/retry OR required first-run setup
Setup: currency + cash -> banks/no-bank -> review + optional debts -> main shell
Main bottom tabs: Home | Overview | Cashflow
  Home: month pager + separate Expenses/refunds and Income tabs
  Overview: monthly totals + wealth/spendable + account cards
  Cashflow: financial projection -> PlanForm
  Transactions: all-date search + type filter
Main drawer: Home, All transactions, Reports, Categories, Accounts, Settings, CSV, Recurring
  Reports replaces content; Back restores the prior main tab
  Accounts -> AccountForm; Categories -> edit dialog
  Recurring -> RecurringForm; unpaid history -> retry/skip
Floating + -> white modal backdrop + Add manually / Scan invoice / From gallery / close
  Manual -> TransactionForm
  Scan -> capture/gallery -> image optimization -> Extract -> invoice review
  Review -> item edit dialogs -> atomic save -> main Home
Existing entry -> TransactionForm, except legacy single-expense receipts -> invoice review
Long-press entries -> bulk category/account/delete actions
```

## Architecture and invariants

- `lib/main.dart` owns startup/theme. `screens/main_screen.dart` owns navigation, lifecycle checks and selection. Navigation uses `MaterialPageRoute`, not named URLs.
- `core/data/ledger_store.dart` is the injected `ChangeNotifier`, public data/write boundary. Forms call store methods; committed changes publish a complete read-only collection snapshot through `refresh()`.
- `core/data/ledger_database.dart` owns schema/migrations; `core/domain/` owns money, schedules and projections. UI components live in `core/presentation/`; invoice code in `features/receipts/`.
- Money is **integer minor units** (2 decimals for EUR/USD/GBP, 3 for IQD), never floating-point. Transactions store positive magnitudes; type determines sign. Refunds reduce spending; transfers affect accounts only. New writes use the setup currency; other-currency rows remain stored and excluded. Upgrades default to EUR without relabeling old amounts.
- Balances derive from opening balance + eligible transactions. Cash cannot overdraw; banks require their own overdraft permission. Blocked accounts can receive funds but cannot fund expenses/outgoing transfers. Preserve historical/future balance validation and atomic rollback.
- Transaction date and UTC creation timestamp are separate; edits preserve creation time. Account opening-date inclusion has legacy semantics that must survive migration.
- Recurring income/expense posting is idempotent. Recurring asset/liability switches are **metadata only**. Outstanding debts are separate liabilities subtracted from account wealth, without changing spending balances. Financial-plan inputs remain independent of accounts and recurring rules.
- Invoice review saves one transaction per nonzero item, negative items as refunds, with no extra total transaction. Total comes from reviewed items. Currency confirmation appears only for missing/mismatched extraction. Every reviewed item has its own editable invoice date; multiple-invoice extraction must supply each date. Oversized photos are downsampled natively, then compressed once and reused; preparation has cancellation and a 45-second per-page limit.

## Read only what you need next

| Task | Read |
| --- | --- |
| Understand screens, find an implementation, select tests | [Screen and source map](docs/APP_MAP.md) |
| Change financial behavior, storage, receipts, CSV or recurring | [Data and workflows](docs/DATA_AND_WORKFLOWS.md) |
| Export/build or port to another platform | [Build and porting](docs/APP_MAP.md#build-export-and-porting) |

The maps cover every `lib/` Dart file. Use their ownership tables to read only affected code/tests. The ignored `Moneva_Codex_Implementation_Prompt.md` contains broader requirements, including unimplemented features; it is not the current feature inventory.

## Verification

```sh
flutter analyze
flutter test
flutter build apk --debug
```

Validation on 2026-10-26: **132 passing tests**, clean analyzer and successful Android debug APK. Phone-sized UI previews were also checked. Do not assume iOS/device camera/release publishing was verified. No full backup/restore, web support, bank integration or cloud sync exists.

Suggested future prompt: **“Read AI_CONTEXT.md first. Use its linked maps only as needed, inspect the files relevant to my request, and preserve the documented financial invariants.”**
