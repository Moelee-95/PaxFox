# Moneva

For a short AI handoff, start with [AI_CONTEXT.md](AI_CONTEXT.md). The [screen/source map](docs/APP_MAP.md) and [data/workflow reference](docs/DATA_AND_WORKFLOWS.md) provide detail on demand.

An offline Flutter personal finance app. Development follows `Moneva_Codex_Implementation_Prompt.md`; this is the first working implementation, not the completed ten-screen specification.

## Implemented

- Income requires a receiving bank or cash account and increases that account's balance. Blocked banks may receive income or incoming transfers; the repository and payment selectors prevent expenses and outgoing transfers from them. Home displays account wealth (all balances, including blocked accounts and overdrafts) separately from balances available to spend. This is account wealth, not a full assets/liabilities net-worth model.
- A Recurring payments section, reachable from the top-left side menu, supports monthly expense and income rules with an every-N-month interval, selected day, payment account, category, start/end dates, editing, pause/resume and deletion. Due bills are posted automatically at startup/resume and on rule save; a manual due-date check is also available. Insufficient funds or a blocked account creates an unpaid occurrence without a partial transaction. Retry or explicitly skip unpaid bills in this section.

- Required first-launch setup: enter cash, add bank accounts (or explicitly indicate no bank account), review and finish. Zero cash is supported. Each bank has a separate Allow overdraft switch; negative bank balances require that switch to be enabled. Accounts and the completion marker are committed together; incomplete setup creates no partial accounts. Subsequent launches skip setup. Existing accounts and ledger data are preserved during upgrade.
- Every expense requires a payment account. Manual entry and invoice review share horizontally scrolling cash/bank account cards; tap the actual account to select it, with a green check indicating the current selection. Blocked accounts cannot fund expenses. Linked payments reduce balances. Cash cannot go below zero; banks can do so only when their own Allow overdraft switch is on. Insufficient-funds errors leave all data unchanged. Editing the source/amount or deleting a payment recomputes balances without double deductions. In Accounts, tap an account to edit its name, type, availability, current balance, or overdraft policy. Correcting a current balance adjusts its original starting balance without adding spending/income or removing payments; historical balances change too. Protected negative history or future balances cause corrections/policy changes to be rejected. Starting dates are preserved during editing.

- Material 3, automatic light/dark theme, four bottom navigation destinations: Home, Overview, Cashflow, Transactions. Overview contains the monthly summary, wealth/spendable totals and horizontally scrolling account balances. Home focuses on its month switcher and selected-month transactions. The floating + button expands Manual and Scan actions over a translucent white backdrop that disables the page underneath. Tap the close button, outside the actions or system Back to cancel. The top-left side menu contains Reports, Categories, Accounts and Recurring payments; The previous Home add button and bottom Add destination are removed. Reports return to the previous main tab with system Back or via Home in the menu.
- Separate expense and income category dropdowns with persisted starter lists. Open Categories from the top-left side menu to add or rename entries and choose a category icon. Seed categories receive matching icons; custom/legacy labels receive a general icon until edited. Category icons appear in the transaction category picker, category management and transaction lists. Expense icons are red, income green, refunds yellow and transfers blue (with a fixed bank-transfer icon). Icon changes immediately update existing transaction rows without changing their financial data. Refunds use expense categories; transfers have no spending category. Names must be nonempty and unique within their list. Renaming updates matching existing transactions and reports atomically.
- Durable SQLite transaction CRUD with confirmation before deletion and immediate dashboard/report refresh.
- Expenses, income, refunds and transfers; validation at form and repository boundaries. Transfers require two different accounts in the same currency and do not affect spending/income. Refunds reduce category spending.
- EUR only for now. Amounts are stored in integer cents; inputs accept comma or point and at most two decimals. Currency selectors are removed from transaction, account and financial-plan forms and ledger filters. Repository writes reject non-EUR transactions, accounts and plans. Legacy non-EUR records are retained in SQLite, excluded from the active app and identified by a dashboard notice; amounts are never relabeled or converted. The legacy decoder remains for compatibility.
- Accounts with currency, signed opening balance, starting date and cash availability flag. New accounts include transactions on their starting date through today. Existing end-of-day snapshots retain the original strictly-after-date rule. Restricted balances are visibly identified.
- Month selection, current-month income/spending/net, recent entries, lazy ledger list, search by description/category/notes, type filters, monthly category reports.
- Persisted single-currency financial plan, explicit manual inputs, month-by-month nominal projections, salary-loss scenario, cash runway, portfolio target, FI coverage and earliest modeled FI month. Missing inputs produce an insufficient-data state; no achieved date is invented when a goal is not reached.

## Run and verify

Requires Flutter compatible with Dart 3.13.3+, Android SDK/JDK for Android, or Xcode on macOS for iOS. Windows desktop also requires the Flutter Windows build toolchain. Dependency versions are locked in `pubspec.lock`.

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter build apk --debug
```

Android/iOS use the native sqflite plugin. Windows/Linux use SQLite FFI. Web is not supported by this implementation (`dart:io` and local SQLite). iOS builds require macOS and have not been verified here. Invoice capture uses cunning_document_scanner and image_picker, matching the reference business_card_reader approach. Android requires API 24+; camera/photo usage descriptions are configured for iOS (target 15.0). Camera capture requires an Android/iOS device; desktop can use gallery images where supported.

## Architecture

```text
lib/
  core/
    domain/
      ledger.dart             # money, accounts, transactions, balance rules
      ledger_queries.dart     # indexed search, monthly summaries, batch balances
      freedom.dart            # financial scenario calculations
      recurring.dart          # monthly schedules and occurrences
    data/
      ledger_database.dart    # SQLite opening, schema, migrations and seed data
      ledger_store.dart       # validated writes, snapshots and change notifications
      transaction_csv.dart    # CSV parsing and serialization
    presentation/             # shared rows, cards, dialogs and action bars
  screens/
    main_screen.dart          # navigation, lifecycle and selection orchestration
    home_screen.dart          # month selection and expense/income browsing
    overview_screen.dart      # monthly metrics and account balances
    reports_screen.dart       # category spending reports
    transactions_screen.dart  # search, type filter and transaction list
    transaction_bulk_editor.dart # bulk-edit choices and commit coordination
    transaction_form.dart     # add/edit/delete form
    accounts_screen.dart      # account management and balance corrections
    setup_screen.dart         # initial account setup
    recurring_screen.dart     # recurring rules and unpaid bills
    freedom_screen.dart       # projections and plan assumptions
  features/receipts/           # invoice extraction, review and images
  main.dart                   # startup, theme and storage failure/retry UI
```

`LedgerStore` is injected into the UI and notifies listeners after committed writes. Domain calculations have no Flutter UI or storage dependencies. SQLite writes involving validation of related accounts execute inside a transaction. Foreign keys and database constraints protect the ledger. Indexes cover transaction date, category, source and destination accounts. Version 1 contains `accounts` and `transactions`, including created/updated timestamps. Version 11 adds optional asset/income and liability/expense labels to recurring rules, defaulting existing rules to off without changing scheduled posting or projections. Version 10 adds scanned invoice batches and transaction links for item-level expenses/refunds, preserving old receipts. Version 9 adds receipts and related item rows with cascading transaction deletion. Version 8 stores expense/income type on recurring rules and occurrences, defaulting existing schedules to expense. Income can be received into blocked accounts; outgoing expense restrictions remain unchanged. Version 7 adds stable category icon identifiers and seeds icon metadata without changing ledger labels or amounts. Version 6 adds `recurring_rules`, `recurring_occurrences`, a due-date index and unique rule/date constraints. Blocked accounts use the existing availability flag (false means blocked). Version 5 adds per-bank overdraft permissions. New banks default to no overdraft; migrated banks retain their previously allowed overdraft behavior until edited. Cash always disallows overdraft. Version 4 adds cash/bank account types and explicit same-day starting-balance behavior. Existing accounts remain bank accounts with unchanged end-of-day snapshot semantics. A persisted setup-completed setting controls first-launch onboarding. Version 3 adds `categories` with separate expense/income lists, retains existing transaction category labels, and seeds starter options. Version 2 adds `settings` for the typed financial plan serialized as JSON. `onUpgrade` preserves version-1 ledger data. Future schema changes must increment the version and migrate existing data; do not reset databases.


### Making changes

| Change | Start here |
| --- | --- |
| Transaction row appearance | `core/presentation/transaction_tile.dart` |
| Summary cards and responsive layout | `metric_card.dart`, `responsive_pair.dart`, `account_balance_card.dart` in `core/presentation/` |
| Pinned save/import buttons | `core/presentation/bottom_action_bar.dart` |
| Confirmation wording/layout | `core/presentation/confirmation_dialog.dart` and its callers |
| Drawer destinations | `core/presentation/main_drawer.dart`, then routing in `screens/main_screen.dart` |
| Home, Overview, Reports or transaction filters | The corresponding screen widget |
| Monthly totals, search or displayed account balances | `core/domain/ledger_queries.dart` |
| Write validation or account protections | `core/data/ledger_store.dart` |
| Database schema or upgrades | `core/data/ledger_database.dart` |

Screens use the injected store; writes go through its methods. Exposed ledger, account, category and recurring collections are read-only. `refresh()` reads one SQLite transaction and publishes the completed snapshot once, so a failed read leaves the previous state available. It also rebuilds category lookups and invalidates derived data after writes.

`LedgerIndex` groups entries by year/month, computes each visited month's summary once, and normalizes searchable text once per snapshot. Home, Overview, Reports and selection share those results. The most recent search result is reused until the query, type or snapshot changes. Account balances are calculated in one ledger pass and cached until the snapshot or local calendar date changes. Cashflow projections are reused while the plan and salary-loss scenario stay the same. The main pager builds pages on demand.

Run the calculation benchmark with `dart run tool/benchmark_ledger.dart`. It checks agreement between individual and batch balances, then reports median timings for 100 accounts and 100,000 synthetic transactions. Cached monthly lookup timings exclude index construction and the first summary calculation. These are calculation measurements, not end-to-end device frame or startup measurements.

## Local data and privacy

The database is `moneva.sqlite` in the platform application-support directory returned by `path_provider`. There is no login, backend, analytics or live exchange-rate service. Tapping Extract uploads the selected photos and expense category names to Gemini directly, as requested. There is no upload confirmation dialog or manual-without-upload route. OS backups may include application support data according to platform policy; custom backup/privacy settings are pending. Do not commit financial workbooks, databases or photos. The private workbook name and SQLite artifacts are gitignored. No private workbook was imported or bundled.

Full backups, JSON restore and XLSX import are **not implemented yet**. CSV import/export is available from the side menu but does not include all application data. Account balance correction exists; a dated reconciliation/audit workflow does not.

## Financial model

Every money input must be explicitly supplied, including known zeros, in EUR. No currency conversion is performed. Portfolio, spendable cash and net passive income are separate inputs, never inferred from one another. Include debt payments in spending, use rental income net of property costs, and exclude property market value, restricted assets and duplicate account cash from the eligible portfolio.

- Annual expense gap = max(0, monthly target spending - monthly net passive income) x 12.
- FI portfolio target = annual gap / withdrawal-rate fraction, rounded up to a minor unit.
- Monthly sustainable portfolio draw = eligible invested portfolio x withdrawal rate / 12.
- Coverage = (net passive income + monthly portfolio draw) / target spending.
- Cashflow before investments = earned income + passive income - spending.
- Runway = unrestricted cash / monthly burn including configured investment contributions; shown as whole months. Nonpositive burn is shown as self-funding under the assumptions.
- Each monthly step grows the portfolio by the annual nominal return / 12 and adds the contribution; spending grows by inflation / 12; passive income grows by its configured annual change / 12. Cash changes by earned + passive - spending - contribution. Growth rounds half away from zero at each monthly boundary using integer/BigInt arithmetic. Percentage inputs are exact basis points.
- The first month where passive income plus illustrative portfolio draw covers that month's inflation-adjusted spending is the modeled FI month. Earned income is excluded from FI coverage. Forecasts run up to 50 years; unattained goals display `Not reached within forecast`.

Example: EUR 2,000 monthly spending less EUR 500 net passive income leaves EUR 18,000 annual gap. A 4% illustrative withdrawal assumption gives EUR 450,000 portfolio target. This rate is editable and not a promise.

Contributions remain an explicit funding assumption throughout the horizon, including after FI; this is an accumulation/coverage model, not a retirement withdrawal simulation. If cash is depleted, later portfolio results are conditional on external funding and the UI says so. The salary-loss switch removes earned income but retains the configured contribution to expose its cash cost. No automatic history-based variable-spending estimate or currency conversion is performed. Returns, inflation and passive growth use consistent nominal monthly rates. These estimates are educational.

## Verification coverage

Domain/SQLite tests verify money precision, refunds, transfer conservation, snapshot date boundaries, nonexistent/mismatched accounts, atomic rejection, update identity/timestamps and deletion. Financial tests cover exact target, already FI, never FI, exact first milestone, zero/invalid inputs, inflation, salary loss, zero earned income, cash depletion and growth rounding. The widget test exercises real temporary SQLite storage through validation, add/edit/delete and dashboard refresh.

## Remaining specification work

- Weekly/yearly recurring schedules and pending-confirmation mode and optional OS notifications. Monthly recurring expenses and income with startup/resume posting are implemented.
- Native offline OCR, item merging and advanced receipt crop/rotation controls beyond the native scanner. Gemini capture/review and private image retention are implemented.
- Section-aware XLSX preview/review, date/currency correction, aliases, provenance, deduplication, atomic commit/rollback and separate opt-in cashflow snapshots.
- Validated portable backups/restore, broader settings and budgets. CSV import/export and extraction timeout settings are implemented. Multi-currency/FX support is deferred while the app is EUR-only.
- Dated reconciliation snapshots/audit history beyond the current starting-balance correction, dated assets/liabilities, net worth and debt planning.
- Full analytics/charting, advanced filters and efficient database pagination (current repository loads the ledger into memory).
- Financial scenario presets/comparison, history-based variable expenses, scheduled/one-off forecast inputs, change schedules, essential-expense targets and charts.
- Import/receipt integration tests, accessibility/device verification and signed release builds.

Current code uses simple injected `ChangeNotifier` state and Navigator routes rather than introducing Riverpod/router/code-generation layers before the remaining feature modules exist. The schema intentionally models the implemented slice only; additional tables belong with their tested vertical slices.

## Latest verification (25 October 2026)

- `dart format lib test`: passed.
- `flutter analyze`: passed, no issues found.
- `flutter test`: passed, 82 tests, including visible CSV import success after scrolling, colored totals in rounded Home tabs, atomic bulk deletion/account/category updates, Home expense/income tabs with refund netting, long-press selection actions and month dragging, unassigned historical expenses and editable account-free history, CSV parsing/round trips, atomic import rollback, duplicate occurrence matching, file selection/preview/import/export widgets, month selector swipes, persisted extraction timeout settings, settings validation and scanner use of longer configured limits, save-button system-inset safety, return to Home after saving from another tab, per-item inline validation errors, repeated-item expansion and exact cent preservation, atomic item-level invoice batches, independent item edits/deletion, shared attachment lifetime, direct extraction without a dialog, cancellation/retry/stale-response isolation, timeout and Back during extraction, synthetic Gemini key-config decryption, mocked multi-image request/response validation, receipt parser validation, editable review widgets, atomic parent/item persistence and rollback, preserved original AI response and receipt category renames, recurring income destinations, blocked-account credits, same-day salary/rent order across multiple months, immutable occurrence type after edits and type-aware category renaming, category icon editing and immediate refresh, transaction-type icon colors and side-menu navigation, required income destinations, blocked balances/wealth, recurring CRUD widgets, startup/resume idempotency, monthly/leap-day scheduling, concurrent catch-up, pause/resume, immutable posted prices, unpaid-bill retry/skip, actual late-payment dates, per-bank overdraft policies, insufficient-funds rollback, account editing, concurrent payments, transfer rejection, funded-income edit/deletion protection, first-launch setup/persistence/idempotency, payment source validation, same-day balances, cash-to-bank edits, negative balances and delete restoration, category management and selection, typed category validation, atomic renaming, EUR-only validation, legacy data preservation, SQLite migration/reopening and cashflow missing-input/salary-loss widget coverage.
- `flutter build apk --debug`: passed; artifact `build/app/outputs/flutter-apk/app-debug.apk`.
- `git diff --check`: passed (only Git line-ending conversion notices).
- No Android/iOS device runtime test or signed release verification was performed. `flutter devices` showed desktop and web targets only. iOS compilation was not attempted on this Windows host.

Protected-account checks run inside SQLite transactions and validate balances by ledger day from the account starting date, including scheduled future entries. Same-day movements are netted because transaction dates have day precision. Future-day funding cannot cover earlier spending. Transaction edits check both previous and new source/destination accounts; deleting income or a transfer is also rejected if it would leave a protected account negative.

## Recurring payment policy

Schedules are local calendar dates, with no UTC-duration arithmetic or weekend adjustment. A day 31 schedule posts on February's last day and returns to the 31st in March. Initial schedules must start today or later, and their first date must be outside any opening snapshot that already includes that day. This prevents silently importing years of historic recurring charges. When reopening the app after missed dates, active rules catch up from their stored next date, with at most 6,000 occurrences per check, processed in date order with income before expenses on the same day. Posting is local bookkeeping; Moneva does not instruct a real bank to pay. No OS background service or notification is installed: due checks happen on app opening/resume, rule save, or manual check; an app left continuously open must be resumed or manually refreshed to check a new date.

Each occurrence and its ledger transaction are committed atomically using a SQLite savepoint, with uniqueness on `(rule_id, scheduled_date)`. Repeated startup/resume/checks cannot create another charge for that date. Unpaid bills keep their original amount, category, account and due date. Explicit retry uses today's actual payment date, preserving the due date in occurrence history, so later funding can pay an earlier bill. Failed bills do not change balances or spending totals. Skipped bills stay skipped; manually deleted posted transactions are not recreated. Posted transaction edits remain independent of rule edits. Category renames update future rules and occurrence labels as well as the ledger.

Pausing stops generation; resuming skips the paused dates and restarts on the next configured day on/after today (resetting the interval anchor). Rule edits affect future occurrences only. Deleting a rule archives its schedule while retaining posted and unpaid history. The payment-history UI shows the latest 100 occurrences; all records remain in SQLite. Existing manual financial-plan assumptions remain separate from recurring rules and are not automatically populated or double counted by the forecast engine.

To add repeating salary or other income: open the side menu, choose Recurring payments, tap Add recurring payment, select Income, then choose an income category, receiving cash/bank account and schedule. Receiving accounts may be blocked; blocked balances remain excluded from spendable balances. Rule type changes affect future occurrences only. Existing posted transactions and pending occurrence snapshots retain their original type.

## Invoice scanning with Gemini

Tap the floating + button, then Scan invoice. Add manually opens the transaction form. Header scan shortcuts are removed. Scanning guidance is available by hovering over or tapping the top-right info icon. Scan more pages and Gallery use compact icon buttons with tooltips. Extract and cancellation controls remain pinned above the bottom safe area, regardless of image count. Document capture opens immediately on Android/iOS. Scan multiple pages, add pages or gallery images, reorder/remove them, then choose Extract. Maximum 10 images, 25 MB per source image and 12 MB combined normalized JPEG data. Each camera or gallery image is optimized immediately after capture, off the UI isolate. Images are oriented without upscaling and retain up to 2,000 pixels on the short edge and 6,000 on the long edge to preserve long-receipt text. JPEG quality starts at 86 and steps down to 82/78 only above a soft 1 MB target; already-small, compatible JPEGs are kept byte-for-byte. Prepared bytes are reused for extraction, retries and saving, avoiding repeated lossy encoding. App-owned temporary copies are cleaned up when pages are removed or scanning closes; original camera/gallery files are never deleted by this cleanup. Extraction starts directly; Cancel extraction and Back remain available, and the whole UI operation uses the timeout configured in Settings (default 180 seconds; adjustable from 30 to 900 seconds). Cancelling closes the active HTTP client and ignores any late response; image processing checks cancellation between pages. The native scanner supplies document detection/cropping; overlap between long-receipt photos is handled by the extraction prompt and still needs user review.

The service sends all pages in one request with current expense category names, asks for JSON with decimal-string prices, and preserves unknown or invalid values for correction rather than fabricating data. Categories not in the supplied list are unset. Review merchant, date, parent category and each item name/price/category. EUR confirmation is shown only when the extracted currency is missing or is not EUR. The saved total is calculated from the reviewed items; charged-total, adjustment and adjustment-note input fields are removed. Quantity and unit-price fields are hidden: integer quantities expand into repeated item rows of one, preserving the exact total by distributing any cent remainder. Weighted/fractional purchase lines remain one charged item. Stored legacy fields are retained for compatibility; new item transactions use quantity one. Add/edit/delete items as needed. Explicit extracted adjustments appear as editable item rows, retaining their descriptions and categories. Edit or remove those rows just like other items. Original extraction data and review guidance are available from the info icon. VAT already included in prices must not be added again. Invoices with a missing or non-EUR currency cannot be saved without explicit EUR confirmation; there is no FX conversion.

Save transactions creates one normal expense per positive-priced item with that item's description, category and amount. Negative discount lines become refunds, and explicit invoice-level adjustments become separate expenses/refunds with the supplied explanation/category. Zero-priced lines remain in the original scan metadata without creating zero-value transactions. The shared invoice date and selected payment account apply to the batch. There is no additional invoice-total expense. Normal account/blocked/overdraft checks apply; all transactions and links commit together or none do. Reports count each transaction once. Photos are normalized into app-private `receipts/` with relative paths, and copied only at save; copied files are removed on failed saves. Each created transaction can be edited/deleted independently through the normal transaction form. Shared source photos remain available from Scanned invoice on each transaction; private images are cleaned up only when the final linked transaction is deleted. Original scanner/gallery cache files remain managed by their plugins/OS; no unrelated gallery originals are deleted. A crash between copying photos and committing SQLite may leave an orphan file; automated orphan sweep and retention settings are pending. OS backup may include receipt photos according to platform policy; app-managed backup remains unimplemented.

New scanned items open in the normal transaction form, with source photos and original extraction available in an expansion. Existing invoices saved by the older single-expense implementation retain their review/edit support and are not silently split during migration. Category renames update saved receipt item labels. No PDF import, cloud image backup or batch multi-invoice extraction is implemented.

### Gemini configuration reused from Card Lens

`gemini_key_provider.dart` reuses the reference project's encrypted remote key fetch/decrypt protocol and URL, `https://alhayali.de/card_lens/gemini-config.json`. It fetches fresh configuration immediately before extraction. It does not copy or embed a plaintext Gemini API key. The bundled decryption key is obfuscation only and cannot keep the service key secret from someone inspecting the client; a server-side proxy with access controls is needed for a public production release. The implementation follows your requested Card Lens method for now. No real key endpoint, quota or paid API call was exercised during automated verification.

The default model matches the reference app, `gemini-3.5-flash-lite`. Override without code changes using `flutter run --dart-define=GEMINI_MODEL=your-enabled-model`. The key must permit that model in your Google project. Requests use `x-goog-api-key` rather than putting the key in a URL, explicit timeouts, JSON response mode and safe errors without logging invoice data or provider response bodies. Non-success, blocked and truncated responses offer retry; nothing is auto-saved. A future secured backend can replace the injectable InvoiceExtractor interface.

Google API references used: https://ai.google.dev/gemini-api/docs/image-understanding and https://ai.google.dev/gemini-api/docs/structured-output .

Transaction and scanned-review Save buttons are pinned in a bottom SafeArea above OS navigation controls. Successful normal transaction saves and scan saves unwind to the main Home tab. Item review shows only name, Price (EUR), and category. On Save, invalid items are outlined in red with specific errors directly below the relevant item; already-valid items are not marked.

Settings is available from the top-left side menu. Invoice extraction timeout is stored locally in the settings table and applied to the next extraction, including the Gemini HTTP request (there is no separate fixed 90-second limit). The default is 180 seconds, with integer values from 30 through 900. The scanner displays actual processing stages and elapsed seconds, not an invented completion percentage. Gemini generateContent/streamGenerateContent does not expose a total-work percentage. Connection/config errors and upstream timeouts can still end a request earlier. Cancel and Back always remain available.


## CSV import and export

Open **side menu > Import & export CSV**. Account and transaction type are optional. Leave Account as Unassigned for historical expenses with unknown payment methods; leave type as Not selected to treat rows as expenses. You can also choose an account and Expense, Income or Refund. Export writes all dates for that account/type; choose a location in the native save dialog. Imports first show a preview and require tapping Import transactions. Back remains available during file operations.

The UTF-8 CSV contains exactly `Date,Details,Category,Cost,Notes more info`. For example:

```csv
Date,Details,Category,Cost,Notes more info
1.10.26,Bank Fee,Service,€4.95,
```

Exports use D.M.YY for years 2000–2099 (otherwise four-digit years), EUR amounts, a UTF-8 BOM and standard quoted fields for commas, quotes and multiline notes. Imports accept comma-, semicolon- and tab-separated files, D.M.YY (2000–2099), D.M.YYYY or ISO dates and decimal points/commas. Use quoted comma-decimal amounts in comma-separated files. Files are limited to 5 MB and 5,000 transactions.

Invalid rows show specific errors and prevent saving. New categories are created with a general icon and existing names matched without case. Save is atomic, including category creation, and applies the usual blocked-account and overdraft rules. Transactions before the account's starting balance are historical and follow the account's existing date semantics. Skip existing matches is enabled by default and compares all five fields plus type/account, preserving genuine repeated purchases by matching occurrence counts. Disable it to intentionally append matching rows.

This format represents one account (or Unassigned) and transaction type per file. Unassigned imports count in spending and reports without changing account balances, remain editable as ordinary transactions and can be assigned an account later. Normal new transactions still require an account. It does not contain the two account links needed for transfers, attachments, recurring rules or account setup and is not a complete app backup. Native file dialogs were compiled for Android; actual device/provider interaction still needs runtime verification.


## Home browsing and transaction selection

Home has a month pager that follows horizontal finger movement; chevrons animate to adjacent months. Under it, Expenses & refunds and Income tabs support tapping and swiping. Spending totals subtract refunds; income totals include income only. Transfers remain in Transactions. Each tab has its own scroll position.

Long-press a transaction on Home or Transactions to enter selection mode, then tap more rows. The top toolbar shows the count, Select all visible and an action menu with Change category, Change account and Delete selected. Back or Close clears selection; changing month, tab, navigation destination or a ledger filter also clears selection. Category changes require a single category kind; transfers are edited individually, and older single-expense invoices use invoice review for category changes. Account changes can assign an account or mark payments Unassigned. Deletes ask for confirmation. Bulk edits/deletes run atomically and validate final balances for every affected account, preserving blocked-account/overdraft policies and receipt attachment cleanup.

Displayed EUR prices use the euro symbol through the currency display formatter. Numeric entry parsing and stored currency codes are unchanged. Home keeps compact Expenses/Income labels inside rounded tabs, with red spending totals and green income totals in both themes. CSV import returns the preview to the top and shows a persistent result card plus an immediate completion message with imported/skipped counts.

## Capture, timestamps and refreshing

Manual transaction entry and invoice review use the same account-card selector. Cards are compact (56 logical pixels at normal text size), show the account name and numeric balance, and use icons instead of cash/bank type labels. Selecting an account places it first and scrolls the row back to the beginning. Incoming income and refunds may use blocked receiving accounts; outgoing expenses and transfers may not. Transfer destination selection and account policy validation are retained. Historical unassigned entries remain supported.

Transaction rows and transaction details show the creation date and time in the device's local time, separately from the selected transaction date. Editing or importing transaction dates does not rewrite the stored creation timestamp. Legacy rows with a missing or invalid timestamp omit it instead of inventing a time.

Pull down on the main data views, Accounts, Categories or Recurring payments to reload local SQLite data, including empty lists. Unsaved forms and capture drafts are not replaced by pull-to-refresh.

Recurring income can be marked Asset, and recurring expenses can be marked Liability. Both are optional stored labels for future features, not changes to balances, automatic payments or financial projections. Existing rules default to neither label. Schedule and recurring-history guidance is behind info buttons with hover tooltips and tap-to-open dialogs.
