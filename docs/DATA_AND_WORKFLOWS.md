# Data rules and workflows

Snapshot: 2026-10-26 / `eb4d9cf`. Read this for behavior/storage changes; [APP_MAP.md](APP_MAP.md) locates files/tests. These contracts describe implementation, not the larger original specification.

## State and persistence

```text
Form/dialog -> LedgerStore public method -> validated SQLite transaction
  -> commit -> refresh(): read consistent snapshot -> replace collections/indexes
  -> notifyListeners -> ListenableBuilder updates UI

LedgerIndex -> visited-month summaries + normalized text + most recent search
currentBalances -> one ledger pass -> cache until snapshot/local day changes
```

No Provider/Riverpod/BLoC/service locator/router framework. Store is injected through constructors. Snapshot lists/sets are unmodifiable; never mutate them to simulate a write. Failed reads retain the last complete snapshot. The entire active ledger is loaded into memory; list rendering is lazy, database pagination is not implemented. `Totals` is a mutable calculation accumulator, not a persisted entity.

SQLite file: `moneva.sqlite` under `getApplicationSupportDirectory()`. Native sqflite on Android/iOS; SQLite FFI selected for Windows/Linux. Private receipt files use relative `receipts/...jpg` paths beneath the same support directory. Prepared scan copies use an app-owned temporary directory. This layout is not a portable backup format.

### Schema 12

This is the logical schema after migrations, not a replacement DDL script. SQL booleans use 0/1; table currency codes use enum names `eur`/`usd`/`gbp`/`iqd`, while invoice JSON uses ISO codes such as `EUR`.

| Table | Fields / relationships |
| --- | --- |
| `accounts` | `id`, name, currency, opening, `as_of`, available, kind, `include_on_as_of`, `allow_overdraft`. |
| `transactions` | `id`, type, positive amount, currency, date, description, category label, `account_id`, `destination_id`, notes, `created_at`, `updated_at`. Both account links reference `accounts`. |
| `debts` | `id`, lender/name, outstanding nonnegative `amount`, currency, UTC `created_at` and `updated_at`. No account FK; not a payment source or expense. |
| `categories` | `id`, kind (expense/income), name, stable string icon ID; case-insensitive name uniqueness within kind. Transactions reference labels, not category IDs. |
| `settings` | key/value text; `setup_completed`, `app_currency` (absent on upgrades means EUR), `invoice_timeout_seconds`. |
| `recurring_rules` | `id`, description, type, amount, category, account FK, day, interval, `next_date`, optional `end_date`, active, archived, `is_asset`, `is_liability`. |
| `recurring_occurrences` | `id`, rule FK, scheduled date and copied type/description/amount/category/account, status, error, transaction FK. Unique rule/date; deleting transaction sets link null. |
| `receipts` | Legacy one-expense receipt: unique transaction FK with cascade delete, total, draft JSON, image paths JSON, raw response, scan time. |
| `receipt_items` | Transaction FK with cascade delete, description, quantity, unit price, total, category, edited flag, position, nullable `item_date` (legacy rows keep null). |
| `scanned_invoices` | Shared batch source: `id`, draft JSON, image paths JSON, raw response, creation time. |
| `scanned_invoice_entries` | Transaction PK/FK with cascade delete, batch FK with cascade delete. Links individual item transactions to shared source. |

Indexes cover transaction date/category/source/destination, recurring due lookup, receipt item transactions and invoice batch links. Foreign keys are enabled on open.

Migration sequence: v1 ledger/accounts; v2 settings; v3 categories; v4 account kinds/opening-day inclusion; v5 overdraft; v6 recurrence; v7 icons; v8 recurring income/expense types; v9 legacy receipts; v10 item batches; v11 asset/liability labels. Old banks retain their previously allowed overdraft policy at v5 migration. V11 labels default off. V12 widens account/transaction currency CHECK constraints while retaining keys, adds debts and receipt item dates. Foreign keys are disabled only while opening/migrating tables, checked during v12 migration, then enabled on open. Increment schema and add forward migration for future persisted fields; never reset a populated database.

## Financial contracts

| Concern | Required behavior |
| --- | --- |
| Money | Integer minor units, EUR/USD/GBP 2 decimals and IQD 3 decimals; comma/point input; no grouping in numeric entry. New amounts positive and at most `9000000000000000` cents. Signed opening balances and invoice line prices have separate handling. |
| Type effects | Expense: source minus, spending plus. Income: source plus, income plus. Refund: source plus, spending minus. Transfer: source minus/destination plus, no income/spending. |
| Assignment | Normal new expenses/income require an account. Historical CSV/bulk unassigned entries count in reports but do not alter balances; edits can retain that state. Refunds may be unassigned. Transfers require two distinct existing same-currency accounts. |
| Availability | Blocked means `available=false`: include in wealth, exclude from spendable, reject expenses/outgoing transfers, allow income/refunds/incoming transfers. |
| Overdraft | Cash never negative; each bank needs explicit overdraft permission. Related writes validate affected accounts' daily balances, including protected historical/future deficits. Bulk operations validate the final combined result. |
| Opening date | New accounts include same-day transactions (`includeOnAsOf=true`); legacy end-of-day snapshots include strictly later dates. Display balances stop at today; reports use selected transaction month, including future dates. |
| Debts | Outstanding liabilities entered in setup or Accounts. Net account wealth = gross account balances minus total outstanding debt; spendable/blocked balances and income/spending reports remain account-based. Borrowed funds already held belong in starting account balances. Repayments are recorded separately as account transactions, then outstanding debt is updated manually; saving/deleting debt never posts a payment. |
| Correction | AccountForm changes opening baseline by desired-current difference, preserving opening date and payments. It is not a reconciliation transaction or independent dated snapshot. |
| Dates | Transaction/schedule days are local calendar `YYYY-MM-DD`. Creation/update times are UTC ISO strings. `createdAt` is read from storage, preserved by edits, displayed locally; invalid/missing legacy times are omitted. |
| Categories | Refunds use expense categories; transfer label is fixed. Rename updates matching ledger, recurring, receipt item and legacy receipt-draft labels atomically; original batch extraction JSON remains source history. Changing an icon does not rewrite money. The picker offers 92 curated built-in Material icons; persisted IDs remain enum names, including all legacy names. No raw glyph codes or new dependencies are stored. |
| Currency | One currency chosen during first-run setup (EUR/USD/GBP/IQD), committed atomically with accounts/debts/setup marker. No FX conversion. Upgrades keep EUR as the active currency. Other-currency records stay stored and excluded from active views; never relabel their amounts. Forms, reports, recurrence, invoice review and CSV use the active currency. Changing currency after setup is not exposed. |

Cashflow is an empty placeholder. Its previous plan model, projection engine, form and store API have been removed. Existing `financial_plan` settings are left untouched as unused legacy data; they are no longer read or written.

## Store API

All methods below are on `LedgerStore` in `lib/core/data/ledger_store.dart`.

| Task | Methods |
| --- | --- |
| Open/read | `open`, `refresh`, `monthSummary`, `searchEntries`, `currentBalances`, `categoriesFor`, `iconFor`. |
| Ledger | `saveEntry`, `deleteEntry`/`deleteEntries`, `updateEntries`; shared private `_writeEntry`, `_checkFunds`. |
| Accounts/onboarding | `addAccount`, `updateAccount`, `completeSetup` (optional selected currency and initial debts), `saveDebt`, `deleteDebt`. |
| Categories | `saveCategory` (also handles rename cascade). |
| Settings | `saveInvoiceTimeout`. |
| CSV | `importCsv`. Codec lives outside store. |
| Recurring | `saveRecurring`, `processRecurring`, `setRecurringActive`, `archiveRecurring`, `retryRecurring`, `skipRecurring`. |
| Receipts | `saveInvoiceBatch`, `scannedInvoiceFor`; legacy `saveInvoice`, `receiptFor`. |

## Invoice flow and attachment lifetime

1. Capture/gallery adds ordered pages, max 10. `InvoiceImagePreparation.prepare` first downsamples oversized sources using Flutter native codecs, then runs orientation/JPEG encoding off the UI isolate, writes owned temp JPEGs and associates prepared bytes with their `File` objects. Extract remains disabled while preparing. The capture screen allows cancellation and times out each page after 45 seconds, stopping the batch; late preparation results are discarded and owned files released. Gallery shortcut opens this same flow with gallery selection instead of camera.
2. No upscaling; cap short edge 2,000px and long edge 6,000px. Start JPEG quality 86, try 82/78 above soft 1 MiB target. Compatible small JPEGs stay byte-identical. Max source 25 MiB; combined prepared upload cap 12 MiB. Soft target is not a guaranteed size or lossless compression.
3. Extractor receives ordered prepared files + expense category names; `bytesFor` reuses preparation for upload and later persistence. Request is Gemini `generateContent`, default `gemini-3.5-flash-lite`, override `GEMINI_MODEL` with Dart define. Fetch encrypted config from `https://alhayali.de/card_lens/gemini-config.json`, send key in `x-goog-api-key`; bundled decryption material is not a server-side secret.
4. Prompt treats receipt text as data, requests actual items/prices/categories/unknowns plus each item’s invoice date, supports multiple invoices (`multiple_invoices` flag), deduplicates overlapping photos and preserves genuine duplicate products. Parse unknown fields for user correction; no auto-save. No offline OCR or PDF import.
5. Review expands integer quantity into individual quantity-one rows, distributing cent remainders exactly. Fractional/weighted lines remain charged lines. Explicit adjustment becomes a visible editable item. Save total is the reviewed item sum, **not an editable extracted charged-total field**. Missing/mismatched currency requires explicit confirmation of the original app currency; no conversion. Validate merchant/category/items, every item date (legacy single-invoice root date can supply it), and positive net total. Review has a date on each item and in its editor; a multi-invoice missing date never inherits another invoice’s root date.
6. Retain image copies, then commit every nonzero item and its metadata/link atomically: positive item -> expense; negative item -> refund. Items use their own invoice dates. Credits are written before gross expenses, then historical/future account balances are validated once against the complete batch so later refunds cannot fund an earlier deficit. No additional invoice-total charge. Failed saves remove newly retained copies and leave no partial batch.
7. Shared source remains reachable from item TransactionForm. Each item can be edited/deleted independently; source files are cleaned when the final linked item is deleted. Legacy `receipts` entries route to invoice review and remain one expense; do not silently split them.
8. Page removal/scan disposal releases only owned preparation files/cache. Never delete gallery originals. Cancel closes the active HTTP client, cancels timers and ignores late responses; isolate processing can finish asynchronously. UI timeout default 180s, configurable 30-900s. Network/config can fail earlier. Persistent orphan sweeping after a crash is not implemented.

## Recurring execution

Monthly expense/income rules only, interval 1-120 months. Days 29-31 clamp to month's last day. First schedule must be today/later and outside opening snapshot coverage. Checks happen on startup/resume, rule save, or manual Check due payments; ordinary pull refresh only reloads storage. No OS background scheduler or real bank payment.

`processRecurring` catches up due dates, up to 6,000 occurrences per check; income precedes expenses on a date. Rule/date uniqueness plus transactional posting prevent duplicates. A failed account/funds check records an unpaid occurrence without a partial charge. Retry uses today's payment date while retaining scheduled history; Skip never posts. Pause stops generation; resume restarts from the next valid date on/after today. Rule edits affect future occurrences; archive preserves history. Posted entries edited/deleted manually are not recreated. Asset applies only to income, Liability only to expenses; both are stored labels for future features.

## CSV and export scope

Exactly five columns: `Date,Details,Category,Cost,Notes more info`. Limits: UTF-8, 5 MiB, 5,000 rows. Import accepts comma/semicolon/tab, ISO or day.month.year dates, decimal point/comma; defaults to unassigned expense. Two-digit years mean 2000-2099. Export uses BOM, quoted fields, app-currency amounts (including IQD precision), day.month.year and selected account/type across all dates.

Preview before committing; any invalid rows prevent import. New categories are created atomically, existing labels matched case-insensitively. Skip-existing compares the five fields plus account/type and occurrence counts, so genuine repeated purchases are retained. Account policies still apply. CSV excludes transfers, photos, debts, setup, recurring and full settings; it is not complete backup/restore.

## Current limits and external boundaries

No login, cloud sync, bank integration, analytics backend, budgets, full backup/restore, XLSX import, FX, native OCR, web runtime, weekly/yearly schedules or notification service. No production signing verification or iOS device validation is implied by debug Android builds. Dependencies and native adapters are mapped in [build/porting](APP_MAP.md#build-export-and-porting).

Private databases, financial workbooks, `/examples`, `/exports` and the original implementation prompt are ignored. Do not use private financial records as test fixtures or log receipt/provider/key contents. Synthetic tests cover behavior without paid Gemini requests.
