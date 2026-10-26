# Screen and source map

Snapshot: 2026-10-26 / `eb4d9cf`. Start with [the short handoff](../AI_CONTEXT.md). Paths below are relative to the repository root. No generated code or platform boilerplate needs reading for normal feature work.

## Navigation and user-visible behavior

| Surface | Entry / ownership | Behavior and exits |
| --- | --- | --- |
| Startup | `MyApp`, `lib/main.dart` | Opens store asynchronously; storage failure offers Retry without reset. Setup marker determines onboarding vs main. Original teal seed, system light/dark theme. |
| Setup | `SetupScreen` | Currency (EUR/USD/GBP/IQD) and cash, banks or explicit no-bank, final review with optional debts. Zero cash supported; bank overdraft/block settings. Finish commits currency, accounts, debts and setup marker atomically. No partial setup writes. |
| Main shell | `MainScreen` | Three lazy pager destinations, synchronized bottom bar and short swipe threshold; drawer and floating add menu. Lifecycle resume checks due recurring rules. |
| Home | `HomeScreen` | Selected month; separate inner Expenses/refunds and Income tabs with their own scroll positions. These do **not** form one continuous pager with Overview. Month changes clear selection. |
| Overview | `OverviewScreen` | Shares selected-month summary. Net, income, spending after refunds; today's wealth, spendable and blocked totals; account cards; unpaid recurring shortcut and legacy-currency notice. |
| Cashflow | `FreedomScreen` | Missing-input state or configured projections; salary-loss scenario; opens `PlanForm`. Manual assumptions, not ledger-derived forecasts. |
| All transactions | `TransactionsScreen` | Drawer destination inside the shell; Back restores prior main tab. All dates; case-insensitive description/category/notes search and type filter. Tap to edit, long-press to select. Filters persist across page recreation. |
| Reports | `ReportsScreen` | Monthly income/spending/net and category spending. Displayed inside shell with pager preserved beneath; Back restores prior tab, drawer Home returns Home. |
| Add menu | `showTransactionMenu` | Anchored to +; Add manually / Scan invoice / From gallery above an X. Translucent white modal barrier blocks background interactions. X, outside tap and Back cancel. Header scan shortcuts are removed. |
| Manual/edit | `TransactionForm` | Visible type selection cards, description, amount, date, category, account cards, notes. Transfers get source/destination cards. Save is pinned; success returns Home. Editing supports confirmed delete, creation time and scanned-source expansion. |
| Scan | `InvoiceScanScreen` | Auto-opens native camera, or gallery when using the floating gallery shortcut. Compact + card below pages expands to scan/gallery icons; remove/reorder pages. Preparation has a 45-second per-page timeout and cancellation. Optimizes new pages before enabling extraction. Extract/progress/cancel stay in bottom safe area. Info icon reveals guidance. Back cancels extraction. |
| Invoice review | `InvoiceReviewScreen` | Photos, merchant/category, account cards, editable items with individual dates (one shared date only for legacy single-expense receipts) and calculated total. No charged-total/adjustment/notes inputs. Conditional app-currency confirmation checkbox. Info exposes guidance/original extraction. Save all together; legacy receipt mode can edit/delete its expense. |
| Item editor | `InvoiceItemDialog` | Dialog with item name, signed price in app currency, category and invoice date; Apply returns a reviewed item. |
| Accounts | `AccountsScreen` -> `AccountForm` | Add/edit name, type, availability, current balance and overdraft. Add/edit/delete outstanding debts; zero records a repaid balance. Debts reduce net account wealth but do not post payments. Current balance correction adjusts opening baseline; existing opening date stays fixed. |
| Categories | `CategoriesScreen` -> `_CategoryDialog` | Expense/income tabs; add/rename and choose stable icon. Rename cascades to matching stored labels. |
| Recurring | `RecurringScreen` -> `RecurringForm` | Monthly expense/income schedules, every-N-months, account/category/day/start/end. Income Asset / expense Liability switches. Edit, pause/resume, archive; posted/failed/skipped history; retry/skip unpaid. Guidance behind info icons. |
| Settings | `SettingsScreen` | Persist invoice extraction timeout, 30-900 seconds, default 180. Applies to next extraction. |
| CSV | `CsvScreen` | Account/type selection, file import preview, duplicate skipping, atomic import and native export save dialog. Default account unassigned; default type expense. Success summary stays visible. |

Shared forms use outlined, floating-label Material inputs in light and dark themes.

Shared interaction rules: transaction selection supports select-all-visible, category/account changes and confirmed bulk deletion. Transfers are edited individually. Back/Close clears selection; navigation/month/tab/filter changes clear it. Main data pages, Accounts, Categories and Recurring support pull-down refresh, including empty lists; unsaved forms/capture drafts are not refreshed away.

## Complete source ownership index

Every production Dart file is listed once. Read a row's file only when that responsibility changes.

### Startup, domain and storage

| File | Responsibility / principal symbols |
| --- | --- |
| `lib/main.dart` | Bootstrap, theme, open/retry storage, setup gate; `MyApp`. |
| `lib/core/domain/ledger.dart` | `Currency`, minor-unit parsing/formatting, `LedgerEntry`, `Account`, `Debt`, `Totals`, `accountBalance`, date helpers. |
| `lib/core/domain/ledger_queries.dart` | `LedgerIndex`, `MonthlyLedger`, `AccountBalances`: indexed search, monthly summaries, one-pass balances. |
| `lib/core/domain/category.dart` | `CategoryKind`, stable `CategoryIcon`, `LedgerCategory`, refund-to-expense kind mapping. |
| `lib/core/domain/recurring.dart` | `RecurringRule`, `RecurringOccurrence`, month-end clamping and first scheduled date. |
| `lib/core/domain/freedom.dart` | `FreedomPlan`, `FreedomProjection`, `projectFreedom`, fixed-precision `grow`. |
| `lib/core/data/ledger_database.dart` | Open SQLite, foreign keys, schema 12, incremental migrations, indexes and category seeds. |
| `lib/core/data/ledger_store.dart` | Public writes and complete snapshots, validation, imports, receipt lifecycle and recurring execution. Method map in [data reference](DATA_AND_WORKFLOWS.md#store-api). |
| `lib/core/data/transaction_csv.dart` | `TransactionCsv`, `CsvPreview`, `CsvTransactionRow`; strict five-column codec, limits/date/money parsing. |

### Screens

All screen files are under `lib/screens/`.

| File | Ownership |
| --- | --- |
| `main_screen.dart` | Shell, navigation, resume checks, add/edit routing and selection orchestration. |
| `setup_screen.dart` | Required onboarding and review. |
| `home_screen.dart` | Month controls and expense/income browsing. |
| `overview_screen.dart` | Monthly metrics and account balance display. |
| `freedom_screen.dart` | Financial projection display, scenario toggle and `PlanForm`. |
| `transactions_screen.dart` | Search/type controls, lazy transaction list. |
| `reports_screen.dart` | Monthly/category report display. |
| `transaction_form.dart` | Manual transaction validation, add/edit/delete. |
| `transaction_bulk_editor.dart` | `TransactionBulkEditor`, typed actions, category/account dialogs and bulk commit coordination. |
| `accounts_screen.dart` | Account list and `AccountForm`. |
| `categories_screen.dart` | Category tabs and `_CategoryDialog`. |
| `recurring_screen.dart` | Rule/history list, retry/skip, `RecurringForm` and classification switches. |
| `settings_screen.dart` | Extraction timeout form. |
| `csv_screen.dart` | File picker/save adapters, preview/import/export UI; injectable file functions for tests. |

### Receipt pipeline

Files are under `lib/features/receipts/`.

| File | Ownership |
| --- | --- |
| `invoice.dart` | `InvoiceDraft`, `InvoiceItem`, JSON parsing, quantity expansion, item errors and total validation. |
| `invoice_scan_screen.dart` | Capture, page order, optimization state, extraction timeout/cancellation and review navigation. |
| `invoice_review_screen.dart` | Review/edit/save and `InvoiceItemDialog`; converts extracted adjustments to visible items. |
| `invoice_image_preparation.dart` | Native codec downsampling, orientation/resize/JPEG policy; isolate encoding; prepared-byte reuse; owned temporary file cleanup. |
| `invoice_images.dart` | Persist private copies, resolve relative paths safely, delete owned attachments. |
| `gemini_invoice_extractor.dart` | Injectable `InvoiceExtractor`; Gemini request, receipt prompt, limits, cancellation and response validation. |
| `gemini_key_provider.dart` | Fetch/decrypt remote encrypted config, safe key-service errors; no plaintext service key embedded. |

### Reusable presentation

Files are under `lib/core/presentation/`.

| File | Ownership |
| --- | --- |
| `entry_type_picker.dart` | Shared visible transaction-type selection cards for manual entry, all-transactions filters, recurring and CSV. |
| `debt_editor.dart` | Shared outstanding-debt editor for setup and Accounts; lender, balance, validation and confirmed deletion. |
| `account_picker.dart` | Shared manual/invoice/transfer account cards; 56px normal height, numeric balance, icon, green check. Selected card moves first and scrolls into view. |
| `account_balance_card.dart` | Overview account balance card. |
| `transaction_tile.dart` | Row appearance, semantic type colors, selection affordance and localized creation timestamp. |
| `transaction_menu.dart` | Floating Manual/Scan/Gallery modal anchored to +. |
| `main_drawer.dart` | Drawer destination enum, labels/icons and selection callback. |
| `month_selector.dart` | Independent draggable month pager and animated chevrons. |
| `metric_card.dart` | Reusable metric display. |
| `responsive_pair.dart` | Two-column layout that stacks on narrow widths/large text. |
| `category_icons.dart` | Category-icon lookup and expense/income/refund/transfer colors. |
| `bottom_action_bar.dart` | Shared safe-area save/import button, busy/disabled presentation. |
| `confirmation_dialog.dart` | Reusable confirmed actions. |
| `info_button.dart` | Hover tooltip and tap-to-open scrollable help dialog. |
| `ledger_refresh.dart` | Shared vertical pull refresh; reload snapshot and show retry feedback on failure. |

## Tests: choose by feature

Files are under `test/`; names below omit `.dart`.

| Feature | Tests |
| --- | --- |
| Money, balances, migrations, CRUD, accounts/categories | `ledger_test`, `account_policy_test`, `currency_debt_test` |
| Cached totals/search/balances and snapshot lifecycle | `ledger_queries_test` |
| Main navigation, onboarding, forms, refresh-visible UI | `widget_test`, `capture_ui_test`, `ui_changes_test` |
| Bulk changes and selection | `bulk_transactions_test` |
| Account cards and select-last-to-start | `account_picker_test` |
| Add overlay, dismissal, disabled background and routing | `transaction_menu_test` |
| Financial projections/rounding | `freedom_test` |
| Recurrence/idempotency/failure and flags/migration | `recurring_test`, `recurring_classification_test` |
| CSV codec/database/native-adapter UI | `transaction_csv_test` |
| Invoice domain, legacy receipts and item batches | `invoice_test`, `invoice_batch_test` |
| Review validation/save and capture UI | `invoice_widget_test`, `capture_ui_test` |
| Scanner timeout/cancel/preparation handoff | `invoice_scan_test` |
| Compression, EXIF, cache, upload bytes and cleanup | `invoice_image_preparation_test` |
| Remote config decryption | `gemini_key_provider_test` |
| Settings persistence/bounds | `settings_test` |

`tool/benchmark_ledger.dart` measures synthetic balance/month lookup calculations, not device frame performance. SQLite widget-test work commonly needs `tester.runAsync`; pump animations separately from real file/isolate/database work.

## Build, export and porting

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Debug APK: `build/app/outputs/flutter-apk/app-debug.apk`. Android identifier: `de.alhayali.moneva`; min SDK 24. `pubspec.yaml` sets app version/SDK/dependencies; `pubspec.lock` pins dependencies. iOS project targets 15.0; native camera/photo descriptions are in `ios/Runner/Info.plist`. Only `android/` and `ios/` platform scaffolds exist in this checkout. Data code supports Windows/Linux FFI, but desktop scaffolds/toolchains still need supplying. Web is not currently supported.

| Port/export concern | Preserve or replace |
| --- | --- |
| Same app, Android package | Existing build config; release currently uses debug signing in `android/app/build.gradle.kts`, so configure real release signing before production distribution. |
| iOS artifact | macOS/Xcode, signing/provisioning and actual plugin/device verification; not established by the Android checks. |
| Reuse logic elsewhere | Preserve integer money, dates, account policies, recurrence and rounding; pure files in `core/domain/` are the main reusable logic. |
| Web/another storage layer | Replace SQLite opening, `dart:io` files, support/temp paths and native dialogs/capture. Preserve store API semantics and atomic writes, not just screen appearance. |
| Scanner/images | Replace `cunning_document_scanner`, `image_picker`, file/compute adapters while retaining ordering, compression policy, review and cancellation. |
| Gemini/network | Keep injectable extractor contract; browser deployment needs a suitable network/key boundary. Client-side config decryption is obfuscation, not secret protection. |
| Data export/migration | Five-column CSV is not a full backup. Full migration also needs settings, categories/icons, account policies/opening semantics, recurring/history, receipt metadata/links and relative image files. |

Ask which target/artifact is wanted if “export the app” is ambiguous. Do not infer a web port from an APK request.
