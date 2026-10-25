# Codex Implementation Brief: Moneva (Flutter)

You are a senior Flutter engineer and software architect. **Implement a working, production-minded, offline-first Flutter application named `Moneva`**, not just a design or scaffold. Moneva is a personal expense, receipt, cashflow, and financial-independence tracker. Prioritize correct functionality, data integrity, maintainability, tests, and responsiveness over polished visuals. The UI will be redesigned incrementally, so keep presentation code easy to replace.

## 1. Working approach and acceptance criteria

- Inspect the existing repository before editing. If no Flutter project exists, create one for Android and iOS with application name `Moneva`, a sensible reverse-domain package identifier, sound lint rules, and a README.
- First provide a concise implementation plan and architecture map; then implement the app. Do not stop after writing a plan, adding TODOs, or drawing mock screens.
- If an optional feature requires unavailable credentials, implement a real functioning offline path and isolate optional integrations behind an interface. Never claim a fake demo is a functional integration.
- Favor cohesive modules and simple, typed APIs. Use `flutter analyze`, `flutter test`, and available build checks; fix errors. If SDK/device/build tooling is unavailable, say exactly what you could and could not verify.
- Use stable, actively maintained, mutually compatible package versions available in the environment. Do not add an unnecessary backend, user login, analytics, cloud sync, or paid AI dependency for v1.
- Financial values must be deterministic; preserve source currencies and never fabricate balances, exchange rates, receipt data, or a financial-freedom date.

## 2. Actual Excel source: understand and import it

The existing personal workbook is named **`Personal Expenses.xlsx`**. It may be made available to you in the working directory or via a user-selected file at runtime. Do not assume Codex can access any earlier chat attachment: ask for the file only if needed for direct inspection; in any case implement runtime XLSX import through the device file picker. Do **not** bundle the user's private workbook in published app assets or commit it to source control.

Workbook structure observed:
- Sheet `Monthly EXPINC`: range around `A1:J1258`, with expense and income records laid out **side by side in the same rows**. Expense-side columns A-F are `#`, `Date`, `Details`, `Category`, `Cost`, `Notes more info`; income-side G-J are `In Date`, `Income Details`, `Amount`, `Notes`. There are repeated monthly header rows, blank spacer rows, section labels, totals and subtotals that are **not transactions**, and some expense rows with missing dates.
- Historic transaction dates span approximately **June 2024–October 2026**, with older entries in IQD and later entries in EUR. **Do not assume currency solely from the year**; implement a section-aware import workflow with user confirmation for currency when not explicit, plus a row-level override.
- Categories contain spelling variations such as `Transporation`, `Rent & Utilites`, `Entertatment`, and other inconsistencies. Offer normalization suggestions while preserving original labels and import provenance. Do not silently reclassify records.
- Sheet `Cashflow`: approximately `A1:L39`, with a mix of salary/passive income, rent from real estate, expense summaries, account/wallet balances, an investment/crypto value, property cost/value, negative liabilities, and historical currency-rate cells. It is a **snapshot/planning sheet**, not a clean transaction ledger. Import these into a separate, reviewable account/asset/liability snapshot flow; never treat account balances or house value as earnings, or count them as new expense transactions. Old exchange-rate cells are historical inputs, **not today's guaranteed market rates**.

Importer requirements:
1. Let the user select `.xlsx` through a file picker, inspect sheets and show a preview before modifying app data.
2. Parse both expense and income halves independently. Detect and exclude repeat headers, totals/subtotals and blank rows. Preserve Excel dates accurately; recognize dates represented by numeric Excel serials and text. Identify missing/ambiguous dates, section boundaries and currencies; do not silently invent an exact date.
3. Show import review: valid rows, skipped rows with reasons, ambiguous rows requiring correction, currencies per section, inferred category aliases, and cashflow snapshot items. Permit correcting unknown dates, currency and category, and excluding individual rows.
4. Import inside an atomic database transaction. Make it idempotent via an import batch ID plus stable source sheet/row/type fingerprint; preview and prevent duplicate imports. Store source identifiers so provenance can be inspected and imports can be safely rolled back by batch.
5. Make account-balance snapshot imports explicitly opt-in. Require the user to confirm whether snapshots are historical or current; preserve an `asOfDate` and avoid double counting them against imported ledger entries.
6. Support export to CSV and JSON backup, with full restore and validation. XLSX export is nice to have after correctness of import, CSV and backup is proven.
7. Test using synthetic XLSX fixtures that replicate the sheet structure. Never include the real financial workbook or receipt photos in repository tests.

## 3. Application scope: ten functional screens

The app must have **10 functional screens**. Use a minimal Material 3 theme and responsive mobile layout; professional and usable, but avoid complex visuals. Bottom navigation: **Home, Transactions, Add (+), Reports, Cashflow**. Recurring, Accounts, and Settings are available through dashboard quick actions / headers; Scanner and Review are nested in the add flow.

### Screen 1 — Home / Dashboard
- Select month, default current month; show income, expenses, net cashflow, available account balances if configured, category breakdown, largest expenses, upcoming recurring transactions, and latest transactions.
- Quick actions: Add expense, Scan receipt, Add income, Recurring rules, Accounts, Import Excel.
- Use actual persisted data. Handle empty state, mixed currencies, incomplete exchange-rate data, and no-account scenarios correctly.

### Screen 2 — Transactions
- Paginated or efficiently streamed expense/income/refund/transfer ledger; search merchant, note, description and receipt item names.
- Filters for date range, category, account, currency, type, recurring/manual/imported, and amount range; sort latest first by default.
- Transaction detail, edit, delete with confirmation, inspect attached receipt image and its extracted line items. Edits must immediately update charts, balances, and forecasts. Do not treat transfers as income or spending.

### Screen 3 — Add / Edit Transaction
- Expense, income, transfer, and refund flows. Amount, currency, date, description/merchant, category, account, notes, tags optional, attachment and editable line items.
- Validate all fields; reject invalid negative amounts, unsupported currencies, nonexistent accounts, and inconsistent receipt totals. Use consistent refund semantics (refund reverses spending in reports rather than inflating salary/income).
- For transfers, require source and destination accounts; update both, without affecting net spending or net worth. Offer save, cancel, and clean edits without duplicating transactions.

### Screen 4 — Receipt Scanner
- Capture a receipt photo with the camera or choose an existing image; permission and error handling; image preview, retake, basic rotate/crop if feasible.
- Integrate **real device OCR**, preferably `google_mlkit_text_recognition` (Latin script, German and English text). Process off the UI path where possible. Extract raw text and use deterministic heuristics to suggest merchant, transaction date, currency, item descriptions, quantities, line totals, discounts and grand total.
- Keep the OCR/parser service injectable and testable. OCR is inherently imperfect: never auto-submit or fabricate values. If scanning fails, route to a fully editable manual entry with the photo retained.
- An optional future AI parser may be defined by an interface, **not** implemented with hardcoded provider credentials. If cloud AI is added later, call it through a properly secured backend with explicit user consent to uploading private receipts.

### Screen 5 — Receipt Review
- **Mandatory review step before saving**. Show original receipt photo and recognized information alongside editable merchant, date, currency, tax, discounts, tip, and each line item (name, quantity, unit price/line total, category).
- Add, delete, merge and edit items; highlight low-confidence extraction and possible total mismatches. Show computed line-item subtotal and receipt grand total and explain discrepancies (discounts, deposits, tax rounding).
- Save a single expense record with related item rows and an attached image. Allow later re-editing without losing the original OCR output. Failed/canceled scans must not create partial transactions.

### Screen 6 — Recurring Payments / Income
- Create, edit, pause, resume, archive and delete recurring **expenses and income** (rent, Deutschlandticket, subscriptions, insurance, salary, net rental income). Support weekly, monthly, yearly frequency, every-N interval, start date, optional end date, due date, payment account, currency, amount, category, and notes.
- Options: automatically post on schedule or create a `pending confirmation` transaction/reminder. Handle weekend and end-of-month rules deliberately (e.g., 31st → last day when chosen), leap years and local timezone/DST.
- **Idempotency is essential**: only one occurrence per rule and scheduled date. Check due occurrences at app startup and app resume so correctness does not depend on background tasks running. Display upcoming occurrences separately from already-posted ledger rows; no double counting. Avoid silently backfilling years of old recurring charges after import.
- Optional local due-date notifications, respecting notification permission and OS limits. Handle price changes for future occurrences without mutating previously posted records. Allow editing a single occurrence without changing the rule.
- The UI may suggest repeating entries detected in historical Excel data, but require explicit approval before creating a rule.

### Screen 7 — Reports / Analytics
- Date and currency selector; month-over-month expense and income trends, spending by category, merchant and item, largest expenses, essential versus discretionary spending, recurring versus variable costs, and savings rate.
- Consider receipt line-item categories when requested, but do not count both a parent receipt and its line items as separate spending. Refunds reduce appropriate net spending. Transfers are excluded from expense and income totals.
- Show clear 'not enough data' states for incomplete exchange-rate information; never sum EUR and IQD as raw numbers. Provide filterable exports.

### Screen 8 — Accounts, Assets & Liabilities
- Accounts: cash, checking, savings, digital wallets, investment accounts, and restricted balances. Configure currency, opening balance, `balanceAsOf`, and subsequent transaction flow.
- Assets: liquid investable holdings, property, and other assets with dated valuations; avoid counting both account cash and a duplicate asset. Liabilities: debts, outstanding obligations and balances, with notes and payment plan optionally.
- Show assets, debts, net worth, liquid assets, and historic snapshots, with no assumptions that all asset values can be spent. Balances should be reproducible based on snapshot and transactions after snapshot; offer reconciliation.
- Distinguish debt *balance* from debt *payment* so an installment doesn't count as both a new expense and an additional liability. Manage cross-currency display using explicit exchange rates.

### Screen 9 — Cashflow & Financial Freedom (critical)
A dedicated **Financial Freedom** screen with two sections or tabs: `Cashflow Forecast` and `Freedom Plan`. This screen must provide actionable projections, not guaranteed predictions.

**A. Current cashflow & runway**
- Current monthly active/earned income, recurring passive income, recurring fixed expenses, estimated variable spending, net monthly cashflow, savings rate, liquid assets, debt balance and net worth.
- Look back at the last 3–6 *complete* months for variable expenses, or allow a user-entered budget when history is sparse or mixes currencies. Exclude transfers and avoid double counting pending recurring events.
- **Runway** = available unrestricted liquid cash / monthly cash burn when burn > 0. If monthly net burn <= 0, show 'currently self-funding under these assumptions'; if balances are unknown, display 'insufficient data'. Do not include property or retirement-restricted assets in immediately spendable runway.
- Forecast monthly balances over 3, 6, 12, 24 and optionally 60 months, combining scheduled recurring income/expenses, estimated variable expenses, known one-offs and configurable income changes. Include a line chart and list of projected months; display the earliest month a projected cash balance reaches zero. Support a scenario such as loss of salary.

**B. Financial independence / 'exit the rat race'**
- Explicitly distinguish:
  1) `Cashflow break-even`: total monthly income covers total monthly spending.
  2) `Work-optional / financially independent`: sustainable passive income **plus** a chosen portfolio withdrawal assumption covers the chosen cost of living **without earned job income**.
  3) Optional milestones: emergency fund, debt-free, 25/50/75/100% FI coverage.
- User-editable assumptions: retirement/desired monthly expenses, essential expenses, net passive income (e.g. rental revenue after rental-specific costs), eligible investable portfolio, monthly investment contribution, nominal annual investment return, annual inflation, annual change in passive income, safe withdrawal rate (default **4% only as an editable illustrative starting assumption**, not a promise), forecast start date and horizon (up to 50 years). Provide conservative/base/optimistic scenario presets; label estimates as educational.
- Baseline annual expense gap = max(0, annual target expenses − sustainable annual non-portfolio passive income). **FI portfolio target = annual expense gap / withdrawal-rate fraction** if rate > 0. Portfolio-based monthly sustainable draw = eligible investable portfolio × withdrawal rate / 12. **FI coverage** = (net passive income + estimated monthly sustainable portfolio draw) / target monthly expenses. Handle zero/negative targets explicitly.
- Forecast month by month using internally consistent nominal assumptions and inflation-adjusted expenses. Grow the investable portfolio using the configured monthly return and contribution while working; account for selected changes to contributions and income. Show the **first month** where the modeled passive income and portfolio withdrawal together cover projected expenses. If never achieved within the selected horizon, show `Not reached within forecast`, not a made-up year. If key values or FX conversions are missing, show `Insufficient data` and ask for the missing inputs.
- Visuals: current FI progress, estimated target portfolio, estimated date (or explicit non-result), projected portfolio versus FI target chart, current runway, debt-free estimate if repayments configured, and scenario comparison.
- Do not equate today's one-off bank balance with an invested portfolio. Property *market value* does not automatically count as investable unless the user explicitly marks it eligible; **net rental income may be passive income** but must not be counted again as a portfolio return or duplicated income. Debts are accounted for separately. Treat these as modeling estimates, never guarantee quitting work by a given date.
- Document the formulas and assumptions in the UI and README. Provide unit tests for exact milestone/runway/forecast math, including zero income, negative cashflow, inflation, incomplete FX, already FI, and never FI.

### Screen 10 — Settings
- Currency/display currency (EUR default; IQD supported), precision/format and manual exchange-rate snapshots with dates; custom categories and original-to-normalized aliases; monthly budgets; privacy; backup/restore; CSV export; Excel import; receipt image storage and retention preferences.
- Allow choosing 12/24-hour time, local date formats, notifications, and default financial model assumptions where applicable. Never upload private financial data without explicit opt-in.

## 4. Core domain / database design

Use a clean feature-first architecture, e.g. `lib/core/`, `lib/features/dashboard/`, `transactions/`, `receipts/`, `recurring/`, `reports/`, `accounts/`, `cashflow/`, `import_export/`, `settings/`. Separate `data`, `domain`, `presentation` where useful; avoid layers that add no value. Recommended: Flutter Material 3 + `flutter_riverpod` for state/injection, `go_router` for navigation, `drift` + SQLite for durable offline storage/migrations, `fl_chart` for charts, `image_picker`/`file_picker` for files, `google_mlkit_text_recognition` for OCR, `path_provider` for private image storage, `intl` for formatting, and an XLSX reader package for imports. Prefer immutable typed models, explicit error handling, structured logging without private content, and strong null-safety.

Use migrations and indexes suitable for a multi-year history. At minimum model:
- `transactions`: id, type, status, description/merchant, date and created/updated timestamps, currency, exact amount, categoryId, accountId, destinationAccountId for transfers, notes, recurringOccurrenceId?, receiptId?, importBatchId?, sourceRowId?.
- `receipt_items`: id, transactionId, description, quantity, unit price, line total, categoryId?, position, userEdited flag.
- `receipts`: id, private image path, thumbnail path?, OCR raw text?, structured parsing metadata?, scannedAt.
- `categories` and `category_aliases`: type, name, optional parent, icon and colors as replaceable UI metadata.
- `recurring_rules` and `recurring_occurrences`: rule, next date, posting behavior, source, unique `(ruleId, scheduledDate)`, occurrence status and generated transactionId.
- `accounts`: type, currency, opening balance, balanceAsOf, availability flag, and investment eligibility flag.
- `assets`, `asset_valuations`, `liabilities` and `liability_snapshots`: dated amounts and eligibility/availability metadata.
- `exchange_rates`: fromCurrency, toCurrency, rate (exact decimal), asOfDate, user-entered/source field; no fabricated live rates.
- `financial_plan`: spending targets, investment contributions, return, inflation, withdrawal rate, expected passive income change, forecast horizon and scenario settings.
- `import_batches`, `import_rows`: provenance, review statuses, row fingerprints, rollback information; `settings` and optional budget targets.

Use **integer smallest currency units** for stored transaction/account money and precise decimal arithmetic for exchange rates, quantities, and forecasts, instead of binary floating-point sums. Respect currency-specific fractions (EUR = 2; IQD handling must be configurable/displayed sensibly, and its ISO exponent must not be assumed to equal EUR). Check safe bounds; round only at defined calculation boundaries. Retain original currencies and rates, and distinguish original from converted totals. Do not silently convert unmatched currencies or use stale currency rates as current ones.

All writes modifying related entities must be atomic. Store receipt photos in app-private storage with relative paths and cleanup on deletion/failed saves. Configure proper backup behavior for local files; image inclusion in backups is opt-in/clearly indicated. Use database indexes for date/category/account/rule IDs, and efficient reactive queries instead of recomputing every transaction on every UI render. Avoid mixing `BuildContext`, network/OCR I/O, or business logic into database and calculation code.

## 5. Core business rules and edge cases

- **Transactions versus snapshots:** Imported historic transactions change spending reports; cashflow sheet balance snapshots do not automatically become new income/expenses. When snapshot opening balance is set for date T, compute forward balances only from relevant later account transactions, or explicitly reconcile double counts.
- **Transfers:** movement between owned accounts is not expense/income, and cannot change combined net worth except recorded fees.
- **Receipts:** item totals must reconcile with parent charged amount allowing explicit discounts/tax/rounding/deposits; report totals must not double count parent and children. OCR may be uncertain; users review before save.
- **Recurring:** project future occurrences independent of persistent posted records; when posted, avoid counting the same occurrence twice. No duplicate posting on app restart or time-zone boundary.
- **Currency:** when selected dashboard period includes mixed currency with no suitable verified/manual FX rate, show per-currency subtotals and a clear missing-rate warning rather than an incorrect grand total.
- **Negative values:** refunds and liabilities have well-defined semantics, not generic negative expenses mixed ambiguously into income.
- **Privacy:** no mandatory sign-in, advertising SDKs, analytics or remote OCR. Do not log personal spending, receipt contents or financial balances. Permissions only when needed. Handle camera/gallery denial gracefully.
- **Accessibility and usability:** readable labels, clear forms, input validation, empty/loading/error states, undo/confirm destructive actions, dark/light theme compatibility, and keyboard-safe forms. UI language can be English first; structure strings for later localization.

## 6. Implementation sequence

Implement in working vertical slices, not isolated presentation mockups:
1. Bootstrap, routing, design tokens, Riverpod dependencies, SQLite schema/migrations, repository interfaces, category seeds, tests.
2. Working transaction CRUD, account handling, balance/currency calculations, dashboard, transaction filters.
3. Recurring rule CRUD, scheduler/occurrence generation and idempotency, pending confirmations.
4. Camera/gallery capture, native OCR, parser, editable receipt review, attached item transactions.
5. XLSX parser and import preview/review/commit, provenance, deduplication, cashflow snapshot opt-in; CSV export and JSON backup/restore.
6. Reports and charts, full Cashflow/Financial Freedom scenario engine and screen.
7. Settings, reminder permissions, polish only enough for robust UX, performance checks, README and release-build verification.

For each slice, ship an actually usable and tested screen/state, not stubs. Do not postpone critical requirements behind TODOs. If a platform limitation prevents a capability, clearly document it and keep a safe manual fallback.

## 7. Tests and verification (required)

- Domain unit tests: money parsing/rounding; multi-currency conversions; date handling; category alias normalization; transfers; refunds; account snapshot balances; net-worth calculation; financial freedom runway, FI formula and projections; 3 scenarios including not-achievable and insufficient data.
- Recurring tests: repeated startup/resume does not duplicate occurrences; last-day-of-month/leap-day behavior; edits/pauses; historic entries excluded; no double counting of pending versus posted entries.
- Import tests: headers/totals excluded, side-by-side expense and income parsed independently, Excel date serials, missing dates require review, currencies require confirmation, duplicate import blocked, rollback atomic, balance snapshot opt-in.
- OCR/parser tests: mock OCR text including German grocery receipt comma decimals, quantity × unit price, discounts, tax, subtotal versus grand total; no item fabrication; edit-before-submit flow.
- Widget/integration tests for navigation, transaction form validation, add/edit/delete, saved receipt review, dashboard refresh, recurring CRUD, cashflow settings/forecasts and import review. Use repository mocks or a temporary SQLite database. No real user files or photos in tests.
- Optimize long transaction lists with lazy builders, debounced search, indexed DB queries and memoized/derived state. Keep animations/charts lightweight. Check Android and iOS camera/photo permission configuration.

## 8. Deliverables

When implementation is complete, provide:
1. The fully working Flutter project with all ten functional screens and no required live backend.
2. A `README.md` with architecture, prerequisites, running/building/testing commands, local data location, privacy model, currency/FX policy, backup/restore/import instructions, receipt/OCR limitations, and the financial freedom formulas with illustrative examples.
3. A brief architecture tree and summary of the database schema, major business logic classes, and migration strategy.
4. A checklist of features implemented, exact tool commands run (analysis/test/build) and their outcomes, plus any honest limitations or remaining work.

**Highest priority:** Moneva must reliably capture/edit expenses; preserve receipt item details; safely import the real-life Excel format; correctly manage recurring entries and financial snapshots; and show an understandable, configurable, mathematically consistent cashflow and financial-independence estimate. A basic UI is acceptable. Incorrect money calculations, fabricated OCR/FX data, duplicate recurring charges, or invented freedom dates are not.
