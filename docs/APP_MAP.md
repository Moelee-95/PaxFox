# Screen and source map

Snapshot: 2026-11-01 / base `eb4d9cf` with local updates. Start with [the short handoff](../AI_CONTEXT.md). Paths below are relative to the repository root. No generated code or platform boilerplate needs reading for normal feature work.

## Navigation and user-visible behavior

| Surface | Entry / ownership | Behavior and exits |
| --- | --- | --- |
| Startup | `MyApp`, `lib/main.dart` | Opens store asynchronously; storage failure offers Retry without reset. Setup marker determines onboarding vs main. Shared Google-style blue Material 3 light/dark themes and offline Roboto. A committed write whose reload fails shows a global reload action, preserving navigation and blocking stale interactions. |
| Setup | `SetupScreen` | Currency (EUR/USD/GBP/IQD) and cash, banks or explicit no-bank, final review with optional debts. Zero cash supported; bank overdraft/block settings. Finish commits currency, accounts, debts and setup marker atomically. No partial setup writes. |
| Main shell | `MainScreen` | Four lazy pager destinations: Home, Overview, Cashflow, More (horizontal three-dot icon), synchronized bottom bar and short swipe threshold. Visited data pages retain state; cached page widgets and scoped listeners avoid rebuilding content when navigation alone changes. Inactive main-page tickers are disabled. No side drawer. Floating add menu is hidden on More. Lifecycle resume checks due recurring rules. Back on a main destination prompts "Tap back again to exit"; a second press within 2 seconds exits. Selection and All transactions close first. On Home's monthly overview, system Back exits an open category to the category list before offering app exit, matching Back to categories. Switching destinations or opening transaction forms resets the exit prompt. |
| Home | `HomeScreen` | Selected month; three tabs: Expenses/refunds, Income and a compact info icon for Monthly overview. Expenses and Income get most of the width, with whole-unit amounts beside their labels (fractional units hidden in this header only). Standard TabBar/TabBarView taps and swipes switch between them. Monthly overview shows net cashflow and category spending with category icons; the month selector stays visible. A leftward drag starting on the info tab hands its edge overscroll to the main pager, revealing Overview with the same finger-tracked transition and bottom-bar synchronization. Rightward swipes still return to Income; a swipe starting on Income ends on the info tab. Month changes clear selection. |
| Overview | `OverviewScreen` | Today's net wealth and spendable totals with large amounts and icon/title headings; compact account cards in a vertical list with wrapping names and edit actions, followed by compact red-highlighted editable debts; no redundant type captions; unpaid recurring shortcut and legacy-currency notice. |
| Cashflow | `CashflowScreen` | Empty placeholder retained in bottom navigation for future functionality. |
| More | `MoreScreen` | Profile card with local name/email editor, options search, colored-icon cards for all former drawer destinations (Home, All transactions, Categories, Accounts, Recurring, CSV, Settings). Management routes return to More on Back. Support group contains Help & FAQ, Rate App, Changelog, Privacy Policy, Terms and Conditions, About; all support actions are deferred by user request. No login/logout. Light/dark and wrapping layouts. |
| All transactions | `TransactionsScreen` | More destination inside the shell; app-bar/system Back restores More. All dates; case-insensitive description/category/notes search and type filter. Tap to edit, long-press to select. Filters persist across page recreation. |
| Add menu | `showTransactionMenu` | Anchored to +; Add manually / Scan invoice / From gallery above an X. Translucent white modal barrier blocks background interactions. X, outside tap and Back cancel. Header scan shortcuts are removed. |
| Manual/edit | `TransactionForm` | Visible type selection cards, description, amount with currency prefix, date, category, account cards, notes. Transfers get source/destination cards. Save is pinned; success returns Home. Editing supports confirmed delete, creation time and scanned-source expansion. |
| Scan | `InvoiceScanScreen` | Auto-opens native camera, or gallery when using the floating gallery shortcut. Compact + card below pages expands to centered labeled Scan/Gallery actions; remove/reorder pages. Preparation has a 45-second per-page timeout and cancellation. Optimizes new pages before enabling extraction. Extract/progress/cancel stay in bottom safe area. Info icon reveals guidance. Back cancels extraction. |
| Invoice review | `InvoiceReviewScreen` | Photos, merchant/category, account cards, editable items with individual dates (one shared date only for legacy single-expense receipts) and calculated total. No charged-total/adjustment/notes inputs. Conditional app-currency confirmation checkbox. Info exposes guidance/original extraction. Save all together; legacy receipt mode can edit/delete its expense. |
| Item editor | `InvoiceItemDialog` | Dialog with item name, signed price in app currency, category and invoice date; Apply returns a reviewed item. |
| Accounts | `AccountsScreen` -> `AccountForm` | Bank/cash section with account icons, tappable policy icons and an inline Add account button. Add/edit name, type, availability, current balance and overdraft. Unused banks offer confirmed deletion; banks linked to transactions or any recurring/history rows and all cash accounts are protected. Add/edit/delete outstanding debts; zero records a repaid balance. Debts reduce net account wealth but do not post payments. List/form guidance lives in header info icons. Current balance correction adjusts opening baseline; existing opening date stays fixed. |
| Categories | `CategoriesScreen` -> `CategoryForm` | Expense/income lists with colored icon circles and add buttons. Full-page editor: type pills (new only; existing type fixed), name beside live icon preview, 21 color swatches, inline search and lazy grouped icon grids, header check and safe-area pinned Save. 113 stable icon IDs include the original 92 and bundled Font Awesome brand icons. Group order starts with Finance for income and Shopping for expenses. Renames cascade to matching stored labels; cancel discards drafts. |
| Recurring | `RecurringScreen` -> `RecurringForm` | Monthly expense/income schedules, every-N-months, account/category/day/start/end. Compact amount/category and day/interval input pairs; end date and Income Asset / expense Liability switch share the bottom row (stack at narrow widths/large text). Save stays above the system navigation inset. Card pause/resume/delete actions are icons; paused schedule text is orange, active text blue. Edit, pause/resume, archive; posted/failed/skipped history; retry/skip unpaid. Guidance behind info icons. |
| Settings | `SettingsScreen` | Persist invoice extraction timeout, 30-900 seconds, default 180. Applies to next extraction; explanatory guidance is in the header info icon. |
| CSV | `CsvScreen` | Multiple account and type selection cards, All toggles, file preview with per-row assignments, duplicate skipping, atomic import and native export save dialog. Defaults include all accounts/types; one nine-column file retains accounts, all four types and transfer destinations. Legacy five-column files require one selected account/type. Transfers match either selected account and export once. Success stays visible; format/import guidance lives in the header info icon. |

Money displays and inputs use comma thousands grouping and dot decimals (e.g. 1,234.56); Home header totals keep their whole-unit display. CSV serialization and extraction JSON retain ungrouped decimals.

Shared forms use outlined Material floating-label inputs and selects (labels rise on focus or when populated) in light and dark themes.

Shared interaction rules: transaction selection supports select-all-visible, category/account changes and confirmed bulk deletion. Transfers are edited individually. Back/Close clears selection; navigation/month/tab/filter changes clear it. Main data pages, Accounts, Categories and Recurring support pull-down refresh, including empty lists; unsaved forms/capture drafts are not refreshed away.

Shared transaction rows on Home, All transactions and inline category browsing show the description in bold and a circular category icon in its saved color (neutral fallback). Category names remain available to accessibility semantics but are not displayed as row headings. Cards have 1px vertical margins, 6px vertical padding, 34px badges, 20px glyphs and 16px headings/prices. A localized Added on timestamp appears below the heading when creation time exists; the transaction date remains separately labeled Date. There is no creation-time info button. Metadata wraps on narrow screens or with large text. Price conveys direction: red minus for expenses, green plus for income/refunds; refunds are labeled. Transfers use a neutral badge, blue unsigned price and transfer arrows. Long descriptions and prices wrap without shrinking money. Existing separate Home tabs, filtering, editing and selection remain in place.

## Complete source ownership index

Every production Dart file is listed once. Read a row's file only when that responsibility changes.

### Startup, domain and storage

| File | Responsibility / principal symbols |
| --- | --- |
| `lib/main.dart` | Bootstrap, font license registration, open/retry storage, setup gate and global store status; `MyApp`. |
| `lib/core/domain/app_failure.dart` | Safe shared failure messages for connections, timeouts, files and HTTP services; excludes private response payloads. |
| `lib/core/domain/number_format.dart` | Exact integer grouping and normalization of grouped UI amounts; no floating-point conversion. |
| `lib/core/domain/ledger.dart` | `Currency`, minor-unit parsing/formatting, `LedgerEntry`, `Account`, `Debt`, `Totals`, `accountBalance`, date helpers. |
| `lib/core/domain/ledger_queries.dart` | `LedgerIndex`, `MonthlyLedger`, `AccountBalances`: lazy normalized search text, cached type filters, indexed monthly category rows, cached rankings/summaries, one-pass balances. |
| `lib/core/domain/category.dart` | `CategoryKind`, stable `CategoryIcon`, `LedgerCategory`, refund-to-expense kind mapping. |
| `lib/core/domain/recurring.dart` | `RecurringRule`, `RecurringOccurrence`, month-end clamping and first scheduled date. |
| `lib/core/data/ledger_database.dart` | Open SQLite, foreign keys, schema 13, incremental migrations (v13 adds nullable category color), indexes and category seeds. |
| `lib/core/data/ledger_store.dart` | Public writes and complete snapshots, validation, imports, receipt lifecycle and recurring execution. Method map in [data reference](DATA_AND_WORKFLOWS.md#store-api). |
| `lib/core/data/transaction_csv.dart` | `TransactionCsv`, `CsvPreview`, `CsvTransactionRow`; nine-column account/type-aware codec, compatible legacy five-column input/output, limits and exact date/money parsing. |

### Screens

All screen files are under `lib/screens/`.

| File | Ownership |
| --- | --- |
| `main_screen.dart` | Shell, navigation, resume checks, add/edit routing and selection orchestration. |
| `more_screen.dart` | Fourth navigation page, `MoreDestination`, lazy searchable options, local profile card and deferred support rows; query and scroll survive main-tab changes. |
| `setup_screen.dart` | Required onboarding and review. |
| `home_screen.dart` | Month controls, expense/income browsing and three-tab navigation including Monthly overview. |
| `monthly_overview.dart` | Home net cashflow and sorted spending-by-category report with category icons, progress bars and refund-aware totals; tap a category to show matching expenses/refunds inline under the heading with a Back to categories button. Rows reuse Home editing, long-press selection and bulk actions; filters/month/tab changes clear selection. No separate date heading. |
| `overview_screen.dart` | Account wealth, spendable/blocked balances and account cards; monthly reporting lives in Home. |
| `cashflow_screen.dart` | Empty Cashflow destination; no financial logic or store dependency. |
| `transactions_screen.dart` | Search/type controls, lazy transaction list. |
| `transaction_form.dart` | Manual transaction validation, add/edit/delete. |
| `transaction_bulk_editor.dart` | `TransactionBulkEditor`, typed actions, category/account dialogs and bulk commit coordination. |
| `accounts_screen.dart` | Account list and `AccountForm`. |
| `categories_screen.dart` | Category tabs, colored icons and add/edit routing. |
| `category_form.dart` | Full-page category add/edit, type selector, live preview, palette, inline grouped icon search, safe async save. |
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
| `invoice_image_preview.dart` | Shared scan/review/source preview, display-sized decoding, cached stored-path resolution and unavailable-image feedback. |
| `invoice_source_details.dart` | Scanned transaction attachments/original output; parses once and handles unavailable or malformed attachment metadata. |
| `gemini_invoice_extractor.dart` | Injectable `InvoiceExtractor`; Gemini request, receipt prompt, limits, cancellation and response validation. |
| `gemini_key_provider.dart` | Fetch/decrypt remote encrypted config, safe key-service errors; no plaintext service key embedded. |

### Reusable presentation

Files are under `lib/core/presentation/`.

| File | Ownership |
| --- | --- |
| `app_theme.dart` | Shared Material 3 palette, offline Roboto typography, cards, navigation and floating-label inputs for both brightness modes. |
| `async_action.dart` | Duplicate-submit guard, safe failure state and disposal-aware completion shared by six form types. |
| `store_status.dart` | Global recovery banner for committed writes awaiting a successful snapshot reload; retries reads only. |
| `retained_page.dart` | Shared keep-alive wrapper for lazily mounted main destinations and Home's inner tabs; preserves scroll/controllers. |
| `entry_type_picker.dart` | Shared single-row, horizontally scrollable transaction-type cards for manual entry, all-transactions filters and recurring; CSV reuses SelectionRow/SelectionCard for multi-selection. |
| `debt_editor.dart` | Shared outstanding-debt editor for setup and Accounts; lender, balance, validation and confirmed deletion; guidance behind a title info icon. Delete/Cancel/Save share one row; outside taps dismiss unsaved drafts, while busy writes block dismissal. |
| `selection_cards.dart` | Shared horizontal SelectionRow and SelectionCard appearance/semantics for transaction types and payment accounts. |
| `account_picker.dart` | Shared manual/invoice/transfer account cards; 56px normal height, numeric balance, icon, green check. Selected card moves first and scrolls into view. Borderless label/card content has no horizontal inset so it aligns with neighboring form fields. |
| `account_balance_card.dart` | Content-sized Overview account card with wrapping name, balance and account edit action. |
| `transaction_list.dart` | Shared lazy transaction sliver for Home expense/income and inline category browsing; shell-supplied row actions. |
| `grouped_amount_formatter.dart` | Shared live amount-input grouping, with decimal precision and caret/selection handling. |
| `transaction_tile.dart` | Description-first cards, saved-color category badges, signed type-colored prices, visible Added on/transaction dates, adaptive wrapping and selection. |
| `transaction_menu.dart` | Floating Manual/Scan/Gallery modal anchored to +. |
| `profile_editor.dart` | Local name/optional email dialog, validation, atomic `saveProfile`, duplicate-submit guard and retryable saves. |
| `month_selector.dart` | Independent draggable month pager and animated chevrons. |
| `metric_card.dart` | Icon/title heading, prominent amount and supporting detail. |
| `responsive_pair.dart` | Two-column layout that stacks on narrow widths/large text. |
| `category_icon_catalog.dart` | Human-readable names and nine display groups for 113 stable icon IDs, including brands. |
| `category_colors.dart` | 21 named ARGB swatches, new-category defaults and contrast-aware foreground helper. |
| `category_icons.dart` | Material/Font Awesome icon lookup, package-aware glyph rendering and default transaction type colors. |
| `bottom_action_bar.dart` | Shared safe-area save/import button, busy/disabled presentation. |
| `confirmation_dialog.dart` | Reusable confirmed actions. |
| `info_button.dart` | Hover tooltip and tap-to-open scrollable help dialog. |
| `ledger_refresh.dart` | Shared vertical pull refresh; reload snapshot and show retry feedback on failure. |

## Tests: choose by feature

Files are under `test/`; names below omit `.dart`.

| Feature | Tests |
| --- | --- |
| Number grouping, precise input and save/edit round-trip | `number_format_test` |
| Money, balances, migrations, CRUD, accounts/categories | `ledger_test`, `account_policy_test`, `currency_debt_test` |
| Cached totals/search/balances and snapshot lifecycle | `ledger_queries_test` |
| Navigation rebuild regression, retained search/scroll and hidden-page live updates with 5,000 entries | `navigation_performance_test` |
| Main navigation, onboarding, forms, refresh-visible UI | `widget_test`, `capture_ui_test`, `ui_changes_test`, `monthly_home_test`, `inline_overview_test`, `clean_layout_test`, `recurring_accounts_layout_test`, `home_edge_swipe_test` |
| More navigation, search, deferred support, local profile persistence/editing and phone layouts | `more_screen_test` (optional `CAPTURE_UI` previews under `build/test-previews/`) |
| Bulk changes and selection | `bulk_transactions_test` |
| Transaction badge/price semantics, tap/long-press, large values and light/dark layouts | `transaction_tile_test` (optional `CAPTURE_UI` previews) |
| Stable icon catalog and legacy IDs | `category_icon_catalog_test` |
| Category color migration/persistence, full-page editor, grouped brand search, save/cancel and layouts | `category_form_test` (optional `CAPTURE_UI` previews) |
| Account cards and select-last-to-start | `account_picker_test` |
| Add overlay, dismissal, disabled background and routing | `transaction_menu_test` |
| Recurrence/idempotency/failure and flags/migration | `recurring_test`, `recurring_classification_test` |
| CSV codec/database/native-adapter UI | `transaction_csv_test` |
| Invoice domain, legacy receipts and item batches | `invoice_test`, `invoice_batch_test` |
| Review validation/save and capture UI | `invoice_widget_test`, `capture_ui_test` |
| Scanner timeout/cancel/preparation handoff | `invoice_scan_test` |
| Compression, EXIF, cache, upload bytes and cleanup | `invoice_image_preparation_test` |
| Remote config decryption | `gemini_key_provider_test` |
| Offline/service/malformed responses, end-to-end timeout, safe async actions, committed reload recovery | `resilience_test` |
| Settings persistence/bounds | `settings_test` |

`tool/benchmark_ledger.dart` measures synthetic snapshot construction, balance/month/category lookups, type filters and first text search, not device frame performance. See [performance notes](PERFORMANCE.md) for measured changes and reproduction. SQLite widget-test work commonly needs `tester.runAsync`; pump animations separately from real file/isolate/database work. `test/helpers/wait_for_store.dart` waits for expected snapshots instead of assuming writes finish within a fixed sleep. Two test workers keep resource use predictable on Windows.

## Build, export and porting

Display branding is Paxlee: Flutter app title and Home header, onboarding, More footer/About subtitle, recurring help, Android label, iOS display/bundle name and CSV export filenames. Internal package/application IDs and the existing database filename retain their original values for update/data compatibility. Bundled Roboto uses the `PaxleeRoboto` family alias.

```sh
flutter pub get
flutter analyze
flutter test --concurrency=2
flutter build apk --release
```

Release APK: `build/app/outputs/flutter-apk/app-release.apk`. Use profile/release on a physical device for performance assessment; debug-mode timings are not representative. `flutter build apk --debug` remains available for debugging. Android identifier: `de.alhayali.moneva`; min SDK 24. `pubspec.yaml` sets app version/SDK/dependencies; `pubspec.lock` pins dependencies. iOS project targets 15.0; native camera/photo descriptions are in `ios/Runner/Info.plist`. Only `android/` and `ios/` platform scaffolds exist in this checkout. Data code supports Windows/Linux FFI, but desktop scaffolds/toolchains still need supplying. Web is not currently supported.

| Port/export concern | Preserve or replace |
| --- | --- |
| Same app, Android package | Existing build config; release currently uses debug signing in `android/app/build.gradle.kts`, so configure real release signing before production distribution. |
| iOS artifact | macOS/Xcode, signing/provisioning and actual plugin/device verification; not established by the Android checks. |
| Reuse logic elsewhere | Preserve integer money, dates, account policies, recurrence and rounding; pure files in `core/domain/` are the main reusable logic. |
| Web/another storage layer | Replace SQLite opening, `dart:io` files, support/temp paths and native dialogs/capture. Preserve store API semantics and atomic writes, not just screen appearance. |
| Scanner/images | Replace `cunning_document_scanner`, `image_picker`, file/compute adapters while retaining ordering, compression policy, review and cancellation. |
| Gemini/network | Keep injectable extractor contract; browser deployment needs a suitable network/key boundary. Client-side config decryption is obfuscation, not secret protection. |
| Data export/migration | Transaction CSV (including account/type metadata) is not a full backup. Full migration also needs settings, categories/icons, account policies/opening semantics, recurring/history, receipt metadata/links and relative image files. |

Ask which target/artifact is wanted if “export the app” is ambiguous. Do not infer a web port from an APK request.
