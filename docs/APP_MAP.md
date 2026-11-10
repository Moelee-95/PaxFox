# Screen and source map

Snapshot: 2026-11-07 / base `eb4d9cf` with local updates. Start with [the short handoff](../AI_CONTEXT.md). Paths below are relative to the repository root. No generated code or platform boilerplate needs reading for normal feature work.

## Navigation and user-visible behavior

| Surface | Entry / ownership | Behavior and exits |
| --- | --- | --- |
| Startup | `MyApp`, `lib/main.dart` | Opens store asynchronously and requests notification permission on startup, including before first-run setup; exact-alarm access is requested when saving a manual reminder. Storage failure offers Retry without reset. Setup marker determines onboarding vs main. Shared Google-style blue Material 3 light/dark themes and offline Roboto. A committed write whose reload fails shows a global reload action, preserving navigation and blocking stale interactions. |
| Notifications | `PaymentNotificationsScreen`, `payment_notifications_screen.dart` | Main header bell with count of manual unposted occurrences; centered PaxFox title on Home. Opens a full-page inbox, catches up due rules and lists every pending occurrence oldest first with account, amount, due date and Confirm paid/received. Successful posting removes the item and updates the badge; failure stays pending with its error. No OS notification permission required. Phone notification body taps open this route and bring the referenced occurrence to the top with a highlighted card; repeated taps reuse an already open inbox. Queued targets survive native initialization until MainScreen is ready. Back restores the main page. |
| Setup | `SetupScreen` | Currency (EUR/USD/GBP/IQD) and cash, banks or explicit no-bank, final review with optional debts. Zero cash supported; bank overdraft/block settings. Finish commits currency, accounts, debts and setup marker atomically. No partial setup writes. |
| Main shell | `MainScreen` | Four lazy pager destinations: Home, Overview, Cashflow, More (horizontal three-dot icon), synchronized bottom bar and short swipe threshold. Visited data pages retain state; cached page widgets and scoped listeners avoid rebuilding content when navigation alone changes. Inactive main-page tickers are disabled. No side drawer. Floating add menu is hidden on More. Lifecycle resume checks due recurring rules and refreshes phone-local reminders. Back on a main destination prompts "Tap back again to exit"; a second press within 2 seconds exits. Selection and All transactions close first. On Home's monthly overview, system Back exits an open category to the category list before offering app exit, matching Back to categories. Switching destinations or opening transaction forms resets the exit prompt. |
| Home | `HomeScreen` | Selected month; three tabs: Expenses/refunds, Income and a compact info icon for Monthly overview. Expenses and Income get most of the width, with whole-unit amounts beside their labels (fractional units hidden in this header only). Standard TabBar/TabBarView taps and swipes switch between them. Monthly overview shows net cashflow and category spending with category icons; the month selector stays visible. A leftward drag starting on the info tab hands its edge overscroll to the main pager, revealing Overview with the same finger-tracked transition and bottom-bar synchronization. Rightward swipes still return to Income; a swipe starting on Income ends on the info tab. Month changes clear selection. New manual entries start in the browsed month; successful manual/scan saves select the saved date (latest reviewed item for multi-date scans). |
| Overview | `OverviewScreen` | Today's net wealth and spendable totals with large amounts and icon/title headings; compact account cards in a vertical list with wrapping names and edit actions, followed by shared compact outlined red debts and green receivables; no redundant type captions; unpaid recurring shortcut and legacy-currency notice. |
| Cashflow | `CashflowScreen` | Empty placeholder retained in bottom navigation for future functionality. |
| More | `MoreScreen` | Profile card with local name/email editor, options search, colored-icon cards for All transactions, Categories, Accounts, Recurring, CSV and Settings. Home is available only in bottom navigation. Management routes return to More on Back. Support group contains Help & FAQ, Rate App, Changelog, Privacy Policy, Terms and Conditions, About; all support actions are deferred by user request. No login/logout. Light/dark and wrapping layouts. |
| All transactions | `TransactionsScreen` | More destination inside the shell; app-bar/system Back restores More. All dates; case-insensitive description/category/notes search and type filter. Tap to edit, long-press to select. Filters persist across page recreation. |
| Add menu | `showTransactionMenu` | Floating + opens Expense (red), Income (green), Transfer (blue). Expense/Income reveal a compact labeled Manual/Scan/Gallery/File grid. Transfer opens its manual editor directly. Fast size/fade/slide transitions; submenu animation respects reduced motion. Back returns to choices before closing; outside/close dismiss either level. Close remains anchored to +; scroll keeps all actions reachable after resizing/large text. |
| Manual/edit | `TransactionForm` | Bottom sheet with colored category/type and editable amount header, description, date/Yesterday, account cards, notes and pinned Save. Foreign-bank selections expose app/native input currency (default app currency) and a conversion preview. Transfers retain source/destination cards; cross-currency transfers require separately entered deducted/received native amounts. Saved monetary details survive non-monetary edits and rate changes. New entries return Home with their actual selected type. Editing retains confirmed delete, creation time and scanned-source expansion. |
| Scan | `InvoiceScanScreen` | Auto-opens native camera, or file picker from Upload file. Expense/income mode controls extraction categories, prompt and review. Compact + card below pages expands to centered labeled Scan/Gallery actions; remove/reorder pages. Preparation has a 45-second per-page timeout and cancellation. Prepares images or PDFs before enabling extraction; original PDF bytes are retained. Extract/progress/cancel stay in bottom safe area. Info icon reveals guidance. Back cancels extraction. |
| Invoice review | `InvoiceReviewScreen` | Photos, merchant/category, account cards, editable items with individual dates (one shared date only for legacy single-expense receipts) and calculated total. No charged-total/adjustment/notes inputs. Conditional app-currency confirmation checkbox. Info exposes guidance/original extraction. Save all together; legacy receipt mode can edit/delete its expense. |
| Item editor | `InvoiceItemSheet` | Shared bottom-sheet editor with item name, signed price in app currency, locked-type category grid and invoice date; Apply returns a reviewed item. Income remains positive-only. |
| Accounts | `AccountsScreen` -> `AccountForm` | Bank/cash section with account icons, tappable policy icons and an inline Add account button. Add/edit name, type, availability, current balance and overdraft. Banks can choose EUR/USD/GBP/IQD; foreign banks require a rate per one app-currency unit and show a live app-currency equivalent. Currency changes convert existing native balances/effects before correction; rate-only changes revalue wealth without changing history. Cash retains app currency. Unused banks offer confirmed deletion; banks linked to transactions or any recurring/history rows and all cash accounts are protected. Add/edit/delete outstanding debts; zero records a repaid balance. Debts reduce net account wealth but do not post payments. List/form guidance lives in header info icons. Current balance correction adjusts opening baseline; existing opening date stays fixed. |
| Categories | `CategoriesScreen` -> `CategoryForm` | Expense/income pill tabs with lazy rounded category cards, saved-color icon circles, kind subtitles, ordinal badges (omitted at narrow large text), row chevrons and an app-bar add button. Picker Edit opens this screen on the matching tab; Back returns to the original picker/draft. Full-page editor: type selection sheet (new only; existing and picker-locked types stay fixed), name beside live icon preview, 21 color swatches, inline search and lazy grouped icon grids, header check and safe-area pinned Save. 113 stable icon IDs include the original 92 and bundled Font Awesome brand icons. Group order starts with Finance for income and Shopping for expenses. Renames cascade to matching stored labels; cancel discards drafts. |
| Recurring | `RecurringScreen` -> `RecurringForm` | Daily/weekly/monthly/yearly expense/income schedules with unit interval, weekday/day/month selectors and start/end. Automatic posting or manual confirmation with reminder time; each overdue occurrence remains separate and confirms on the confirmation date. Foreign accounts expose app/native currency; choosing an account defaults to its native currency. Each posting freezes the then-current conversion; unpaid retries retain the scheduled input amount/currency. Bottom-sheet editor with shared category/type and amount header; day/interval input pair; end date and Income Asset / expense Liability switch share the bottom row (stack at narrow widths/large text). Save stays above the system navigation inset. Reference-style rounded cards use expense-red/income-green outlines/tints, category badges, prominent amounts, status corner labels and due footers. A smaller native switch controls active/paused status through the existing store API; per-rule optimistic save state keeps other controls enabled and prevents the whole screen flashing disabled; tapping a card edits it. A larger delete icon sits beside the switch. Compact 16px rounded cards omit the badge row for ordinary future payments; meaningful due/paused/ended badges remain. Earliest unpaid occurrences determine overdue/today status even after the next schedule advances. Narrow/large-text cards stack their amount/control row. Edit, pause/resume, archive; posted/failed/skipped history; retry/skip automatic failures and confirm manual payments. Guidance behind info icons. |
| Settings | `SettingsScreen` | Persist invoice extraction timeout (30-900 seconds, default 180), HTTPS encrypted JSON source URL and online/manual Gemini key selection. Manual keys are obscured in the form and stored locally in settings. The info icon beside the manual-key help text explains setup and opens `https://aistudio.google.com/apikey` in the external browser; a selectable link remains available if opening fails. Applies to next extraction; timing guidance is beside the Invoice scanning heading. |
| CSV | `CsvScreen` | Multiple account selection cards and a type selection bottom sheet with staged Apply, All toggles, file preview with per-row assignments, duplicate skipping, atomic import and native export save dialog. Defaults include all accounts/types; one file retains accounts, all four types and transfer destinations; foreign-currency exports add five native-currency/FX columns to the normal nine-column format. Legacy five-column files require one selected account/type. Transfers match either selected account and export once. Success stays visible; format/import guidance lives in the header info icon. |

Money displays and inputs use comma thousands grouping and dot decimals (e.g. 1,234.56); Home header totals keep their whole-unit display. CSV serialization and extraction JSON retain ungrouped decimals.

Shared forms use outlined Material floating-label inputs and selects (labels rise on focus or when populated) in light and dark themes.

Shared interaction rules: transaction selection supports select-all-visible, category/account changes and confirmed bulk deletion. Transfers are edited individually. Back/Close clears selection; navigation/month/tab/filter changes clear it. Main data pages, Accounts, Categories and Recurring support pull-down refresh, including empty lists; unsaved forms/capture drafts are not refreshed away.

Shared transaction rows on Home, All transactions and inline category browsing show the description in bold and a circular category icon in its saved color (neutral fallback). Category names remain available to accessibility semantics but are not displayed as row headings. Cards have 1px vertical margins, 6px vertical padding, 34px badges, 20px glyphs and 16px headings/prices. A localized creation timestamp with a history icon appears below the heading when available; the transaction date appears below the price without a Date prefix. Tooltips identify the two dates. Scanned invoice items share one thin rounded outline, invoice-number/merchant heading, visible-item count and total. Header taps collapse/expand that invoice, showing only the header when collapsed. Totals match filtered visible items, subtract refunds and keep currencies separate. Grouping is scoped to current search/month/type/category results and anchored at the first matching entry; other matching invoice items move together while preserving their relative order. Each item remains lazily rendered and independently editable/selectable. There is no creation-time info button. Metadata wraps on narrow screens or with large text. Price conveys direction: red minus for expenses, green plus for income/refunds; refunds are labeled. Transfers use a neutral badge, blue unsigned reporting price and transfer arrows. FX rows also show the saved original bank amount/rate; cross-currency transfers show both original supplied amounts and their actual rate. Long descriptions and prices wrap without shrinking money. Existing separate Home tabs, filtering, editing and selection remain in place.

## Complete source ownership index

Every production Dart file is listed once. Read a row's file only when that responsibility changes.

### Startup, domain and storage

| File | Responsibility / principal symbols |
| --- | --- |
| `lib/main.dart` | Bootstrap, font license registration, open/retry storage, setup gate and global store status; `MyApp`. |
| `lib/core/domain/app_failure.dart` | Safe shared failure messages for connections, timeouts, files and HTTP services; excludes private response payloads. |
| `lib/core/domain/number_format.dart` | Exact integer grouping and normalization of grouped UI amounts; no floating-point conversion. |
| `lib/core/domain/exchange_rate.dart` | Exact positive decimal rates (up to 9 decimals), BigInt rational conversions and nearest-minor-unit rounding halfway away from zero. |
| `lib/core/domain/ledger.dart` | `Currency`, minor-unit parsing/formatting, `LedgerEntry`, immutable original `FxSnapshot`, `Account`, `Debt`, `Totals`, `accountBalance`, date helpers. |
| `lib/core/domain/ledger_queries.dart` | `LedgerIndex`, `MonthlyLedger`, `AccountBalances`: lazy normalized search text, cached type filters, indexed monthly category rows, cached rankings/summaries, one-pass balances. |
| `lib/core/domain/category.dart` | `CategoryKind`, stable `CategoryIcon`, `LedgerCategory`, refund-to-expense kind mapping. |
| `lib/core/domain/recurring.dart` | `RecurringRule`, `RecurringOccurrence`, daily/weekly/monthly/yearly calendar helpers and short-month/leap-day clamping. |
| `lib/core/data/ledger_database.dart` | Open SQLite, foreign keys, schema 18, incremental migrations (v18 adds debt deadlines/acknowledgements; v17 adds native settlement metadata/fees; v16 adds debt direction, settlement/conversion links and triggers, and protected Debt expense/income categories), indexes and category seeds. |
| `lib/core/data/ledger_store.dart` | Public writes and complete snapshots, validation, imports, receipt lifecycle and recurring execution. Method map in [data reference](DATA_AND_WORKFLOWS.md#store-api). |
| `lib/core/data/recurring_notifications.dart` | Android/iOS reminders, permissions, phone-zone refresh and foreground/launch Confirm handling; SQLite pending items remain authoritative. |
| `lib/core/data/transaction_csv.dart` | `TransactionCsv`, `CsvPreview`, `CsvTransactionRow`; nine-column account/type-aware codec, optional five native/FX metadata columns, compatible legacy five-column input/output, limits and exact date/money parsing. |

### Screens

All screen files are under `lib/screens/`.

| File | Ownership |
| --- | --- |
| `main_screen.dart` | Shell, navigation, resume checks, add/edit routing and selection orchestration. |
| `more_screen.dart` | Fourth navigation page, `MoreDestination`, lazy searchable options, local profile card and deferred support rows; query and scroll survive main-tab changes. |
| `setup_screen.dart` | Required onboarding and review. |
| `home_screen.dart` | Month controls, expense/income browsing and three-tab navigation including Monthly overview. |
| `monthly_overview.dart` | Home net cashflow and sorted spending-by-category report with category icons, progress bars and refund-aware totals; tap a category to show matching expenses/refunds inline under the heading with a Back to categories button. Rows reuse Home editing, long-press selection and bulk actions; filters/month/tab changes clear selection. No separate date heading. |
| `overview_screen.dart` | Account wealth including liabilities/receivables, spendable/blocked balances and account cards (app-currency value prominent; native value beneath without a rate); separate Debts and Money owed to you sections each have totals/add controls; Pay/Receive actions open linked partial/full settlement editors; monthly reporting lives in Home. |
| `cashflow_screen.dart` | Empty Cashflow destination; no financial logic or store dependency. |
| `transactions_screen.dart` | Search/type controls, lazy transaction list. |
| `transaction_form.dart` | Manual transaction validation, add/edit/delete and editable Added on beneath Date; optional debt prefill locks the protected category/type and saves a linked settlement. |
| `transaction_bulk_editor.dart` | `TransactionBulkEditor`, typed actions, category/account dialogs and bulk commit coordination. |
| `accounts_screen.dart` | Account list and `AccountForm`. |
| `categories_screen.dart` | Category tabs, colored icons and add/edit routing. |
| `category_form.dart` | Full-page category add/edit, type selector, live preview, palette, inline grouped icon search, safe async save. |
| `payment_notifications_screen.dart` | Durable manual recurring-payment inbox, confirmation and conversion to debts/receivables, shared pending-occurrence filter for the main-header badge. |
| `recurring_screen.dart` | Rule/history list, retry/skip, `RecurringForm` and classification switches. |
| `settings_screen.dart` | Immediate persistent payment-reminder notification switch (off cancels phone reminders while preserving the inbox; on requests phone permission and refreshes reminders), extraction timeout, encrypted config URL, manual Gemini key/source form and Google AI Studio key-help dialog (`url_launcher` external browser). |
| `csv_screen.dart` | File picker/save adapters, preview/import/export UI; CSV parsing/export preparation in workers; injectable file functions for tests. |

### Receipt pipeline

Files are under `lib/features/receipts/`.

| File | Ownership |
| --- | --- |
| `invoice.dart` | `InvoiceDraft`, `InvoiceItem`, JSON parsing, quantity expansion, item errors and total validation. |
| `invoice_scan_screen.dart` | Capture, page order, optimization state, extraction timeout/cancellation and review navigation. |
| `invoice_review_screen.dart` | Expense/income review/edit/save and `InvoiceItemSheet`; expense adjustments become visible items; income uses positive payments and receiving accounts. |
| `invoice_image_preparation.dart` | Validated PDF passthrough; Android/iOS native sampled decode and single JPEG encode (4 MP cap), serialized retry/cancellation, prepared-byte reuse and owned temporary file cleanup; bounded desktop/test fallback. |
| `invoice_images.dart` | Persist private copies, resolve relative paths safely, delete owned attachments. |
| `invoice_image_preview.dart` | Shared scan/review/source preview, display-sized decoding, cached stored-path resolution, PDF document cards and unavailable-image feedback. |
| `invoice_source_details.dart` | Scanned transaction attachments/original output; parses once, shows loading progress and handles unavailable or malformed attachment metadata. |
| `gemini_invoice_extractor.dart` | Injectable `InvoiceExtractor`; Gemini request, receipt prompt, limits, cancellation and response validation. |
| `gemini_key_provider.dart` | Fetch/decrypt remote encrypted config, safe key-service errors; no plaintext service key embedded. |

### Reusable presentation

Files are under `lib/core/presentation/`.

| File | Ownership |
| --- | --- |
| `fox_head_icon.dart` | Small theme-colored vector fox silhouette for Cashflow, painted at icon size without image decoding. |
| `floating_navigation_bar.dart` | Main bottom capsule styled with theme-aware gradients, subtle borders/shadows and purple selected icons/labels. A 180ms directional pill animates independently inside a repaint boundary; no blur or page rebuilding. Reduced motion disables animation; navigation-label scaling caps at 1.3 to fit compact destinations. Retains standard NavigationBar semantics, RTL layout and safe-area handling. |
| `outlined_tabs.dart` | Shared Categories/Home pill TabBar: rounded 2px outline, 8% tint, bold selected labels, and controller-driven interpolated red/green/blue color during taps and swipes. Home retains unequal money/info widths. |
| `app_theme.dart` | Original blue/neutral Material 3 light/dark themes, offline Roboto, standard buttons, cards and navigation. Brand-orange experiment reverted by user request. |
| `async_action.dart` | Duplicate-submit guard, safe failure state and disposal-aware completion shared by six form types. |
| `store_status.dart` | Global recovery banner for committed writes awaiting a successful snapshot reload; retries reads only. Independent refresh spinner leaves retained page content unchanged. |
| `busy_label.dart` | Shared button label with an animated loading spinner, also used for background action feedback. |
| `retained_page.dart` | Shared keep-alive wrapper for lazily mounted main destinations and Home's inner tabs; preserves scroll/controllers. Optional active flag defers hidden inner-tab child updates; main destinations remain live by default. |
| `app_sheet.dart` | Shared modal constraints, safe-area/dismissal policy and bounded selection-sheet frame. |
| `category_picker.dart` | Lazy saved-color/icon grid, allowed-type tabs, add/edit CategoryForm routing, validation and stable-ID rename handoff. |
| `entry_editor_sheet.dart` | Transaction/recurring/item editor layout, pinned Save, colored header, keyboard compaction and preserved field identity. |
| `entry_type_picker.dart` | Type label/icon/color helpers, type field and single/multi-select bottom sheet. All-transactions supports All types; CSV stages selections until Apply. |
| `debt_editor.dart` | Shared liability/receivable editor for setup, Overview and Accounts; lender, balance, validation and confirmed deletion; guidance behind a title info icon. Delete/Cancel/Save share one row with consistent unscaled text; outside taps dismiss unsaved drafts, while busy writes block dismissal. |
| `selection_cards.dart` | Shared horizontal SelectionRow/SelectionCard appearance for payment accounts and CSV account multi-selection. |
| `account_picker.dart` | Shared manual/invoice/transfer account cards; 56px normal height, numeric balance, icon, green check. Selected card moves first and scrolls into view. Borderless label/card content has no horizontal inset so it aligns with neighboring form fields. |
| `account_balance_card.dart` | Content-sized Overview account card with wrapping name, balance and account edit action. |
| `transaction_list.dart` | Shared lazy transaction sliver for Home, All transactions and inline category browsing; groups visible scanned invoice items with one tappable heading/count/total and a continuous outline painted across lazy rows; collapsed groups render only their header, and collapse choices survive mounted-list filter/snapshot updates; shell-supplied row actions. |
| `grouped_amount_formatter.dart` | Shared live amount-input grouping, with decimal precision and caret/selection handling. |
| `transaction_tile.dart` | Description-first cards, saved-color category badges, signed type-colored prices, history-icon creation timestamp, unprefixed date beneath price, adaptive wrapping and selection. |
| `recurring_payment_card.dart` | Shared stateless recurring-rule card with category icon/color, native amount, daily/weekly/monthly/yearly schedule labels, active switch, due/paused/ended badges/footer, adaptive layout and edit/delete callbacks. |
| `transaction_menu.dart` | Stateful progressive creation panel; three top-level choices and one selected entry-method grid, responsive 300px maximum width, anchored close, dim backdrop and quick animated transitions. Requests reuse existing manual/document routes. |
| `profile_editor.dart` | Local name/optional email dialog, validation, atomic `saveProfile`, duplicate-submit guard and retryable saves. |
| `month_selector.dart` | Independent draggable month pager; commits after settling, 180ms chevrons and accumulated rapid-tap destinations. |
| `metric_card.dart` | Icon/title heading, prominent amount and supporting detail. |
| `responsive_pair.dart` | Two-column layout that stacks on narrow widths/large text. |
| `category_icon_catalog.dart` | Human-readable names and nine display groups for 113 stable icon IDs, including brands. |
| `category_colors.dart` | 21 named ARGB swatches, new-category defaults and contrast-aware foreground helper. |
| `category_icons.dart` | Material/Font Awesome icon lookup, package-aware glyph rendering and default transaction type colors. |
| `bottom_action_bar.dart` | Shared safe-area save/import button, busy/disabled presentation and optional button styling. |
| `confirmation_dialog.dart` | Reusable confirmed actions. |
| `info_button.dart` | Hover tooltip and tap-to-open scrollable help dialog. |
| `ledger_refresh.dart` | Shared vertical pull refresh; reload snapshot and show retry feedback on failure. |

## Tests: choose by feature

Files are under `test/`; names below omit `.dart`.

| Feature | Tests |
| --- | --- |
| Number grouping, precise input and save/edit round-trip | `number_format_test` |
| Money, balances, migrations, CRUD, accounts/categories | `ledger_test`, `account_policy_test`, `currency_debt_test` |
| Bottom sheets, draft cancellation/retention, locked types, category add/rename, multi-select Apply, lazy catalogs and keyboard layouts | `bottom_sheets_test` (optional `CAPTURE_UI` previews) |
| Cached totals/search/balances and snapshot lifecycle | `ledger_queries_test` |
| Month slide/tap consistency and loading feedback without content rebuilds | `month_navigation_test`, `loading_feedback_test` |
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
| Income documents, net payment filtering, PDF bytes/MIME, receiving accounts and Home return | `income_documents_test` |
| Review validation/save and capture UI | `invoice_widget_test`, `capture_ui_test` |
| Scanner timeout/cancel/preparation handoff | `invoice_scan_test` |
| Compression, EXIF, cache, upload bytes and cleanup | `invoice_image_preparation_test` |
| Remote config decryption | `gemini_key_provider_test` |
| Offline/service/malformed responses, end-to-end timeout, safe async actions, committed reload recovery | `resilience_test` |
| Foreign account migration, frozen reporting/native balances, exact conversions, transfers, recurrence/retry, CSV and editor defaults | `foreign_currency_test`, `foreign_currency_widgets_test` |
| Calendar schedules, separate manual occurrences, confirmation idempotency, created time and invoice labels | `recurring_schedule_test` |
| Native reminder requests, rolling window, time-zone updates and Confirm actions | `recurring_notifications_test` |
| In-app payment inbox, badge, confirmation removal and failed-charge retention | `payment_notifications_test` |
| Debt category protection, partial settlement/edit/delete/rollback, receivables, reminder conversion, schema-15 migration and editor/account display | `debt_workflow_test` |
| Settings persistence/bounds | `settings_test` |

`tool/benchmark_ledger.dart` measures synthetic snapshot construction, balance/month/category lookups, type filters and first text search, not device frame performance. See [performance notes](PERFORMANCE.md) for measured changes and reproduction. SQLite widget-test work commonly needs `tester.runAsync`; pump animations separately from real file/isolate/database work. `test/helpers/wait_for_store.dart` waits for expected snapshots instead of assuming writes finish within a fixed sleep. Two test workers keep resource use predictable on Windows.

## Build, export and porting

Launcher artwork is preserved at `assets/branding/app_icon_source.png`. Run `dart run tool/generate_app_icons.dart` from the repository root to regenerate Android density-specific legacy/adaptive icons and the iOS AppIcon catalog. The generator fills the source's black outer corners with navy, keeps adaptive artwork within the safe area and emits opaque iOS images. The source is a build input, not a runtime asset.

Display branding is PaxFox: Flutter app title and Home header, onboarding, More footer/About subtitle, recurring help, Android label, iOS display/bundle name and CSV export filenames. Internal package/application IDs and the existing database filename retain their original values for update/data compatibility. Bundled Roboto uses the `PaxFoxRoboto` family alias.

```sh
flutter pub get
flutter analyze
flutter test --concurrency=2
flutter build apk --release
```

Release APK: `build/app/outputs/flutter-apk/app-release.apk`. Use profile/release on a physical device for performance assessment; debug-mode timings are not representative. `flutter build apk --debug` remains available for debugging. Android identifier: `de.alhayali.moneva`; min SDK 24. `pubspec.yaml` sets app version/SDK/dependencies; `pubspec.lock` pins dependencies. iOS project targets 15.0; native camera/photo descriptions are in `ios/Runner/Info.plist`. Local reminders use `flutter_local_notifications`, `timezone` and `flutter_timezone`; Android enables desugaring, notification/exact-alarm/reboot permissions and plugin receivers; iOS sets its notification-center delegate and foreground Confirm category. The data reference documents reminder limits. After native image-processing edits or adding native plugins, stop the current Flutter run/debug session and Run `lib/main.dart` again to rebuild; hot reload and hot restart do not compile native changes. Only `android/` and `ios/` platform scaffolds exist in this checkout. Data code supports Windows/Linux FFI, but desktop scaffolds/toolchains still need supplying. Web is not currently supported.

For reproducible synthetic device frame measurements, `tool/profile_navigation.dart` uses an in-memory ledger and the opt-in Gradle property `paxfoxBenchmark=true` to install under `de.alhayali.moneva.benchmark`. See PERFORMANCE for exact commands and cleanup. Normal builds keep the existing app ID.

| Port/export concern | Preserve or replace |
| --- | --- |
| Same app, Android package | Existing build config; release currently uses debug signing in `android/app/build.gradle.kts`, so configure real release signing before production distribution. |
| iOS artifact | macOS/Xcode, signing/provisioning and actual plugin/device verification; not established by the Android checks. |
| Reuse logic elsewhere | Preserve integer money, dates, account policies, recurrence and rounding; pure files in `core/domain/` are the main reusable logic. |
| Web/another storage layer | Replace SQLite opening, `dart:io` files, support/temp paths and native dialogs/capture. Preserve store API semantics and atomic writes, not just screen appearance. |
| Scanner/images | Native channel `paxfox/invoice_images` is registered by Android `MainActivity.java`/`InvoiceImageEncoder.java` and iOS `AppDelegate.swift`; background sampled decoding, EXIF and JPEG encoding. Replace `cunning_document_scanner`, `image_picker`, file/compute adapters while retaining ordering, compression policy, review and cancellation. |
| Gemini/network | Keep injectable extractor contract; browser deployment needs a suitable network/key boundary. Client-side config decryption is obfuscation, not secret protection. |
| Data export/migration | Transaction CSV (including account/type metadata) is not a full backup. Full migration also needs settings, categories/icons, account policies/opening semantics, recurring/history, receipt metadata/links and relative image files. |

Ask which target/artifact is wanted if “export the app” is ambiguous. Do not infer a web port from an APK request.

## Monthly savings chart

Overview includes `core/presentation/monthly_savings_chart.dart`, a reusable stateful FL Chart bar card supplied with currency and an indexed monthly-report callback. It keeps month selection/history locally, shows six months at every phone width, permanent compact bar amounts (including zeros), touch tooltips, accessible month buttons, earlier/later controls capped at the current month, and exact income/expense/net values. It uses the existing blue light/dark themes. `fl_chart` 1.3.0 is MIT-licensed; the dependency also provides reusable line/pie/scatter/radar chart APIs for future features. `monthly_savings_chart_test.dart` covers financial type/currency filtering, touch selection, history, refresh retention, empty data and IQD large-text layouts.


### Native debt currencies and shared presentation
- `core/domain/currency_exchange.dart`: exact rational direct/inverse/cross rates and final minor-unit rounding; no network rates.
- `core/presentation/debt_balance_card.dart`: shared compact red/green outlined liability/receivable card in Overview and Accounts; main-currency value above native value and matching outlined action.
- `screens/currency_exchange_screen.dart`: Settings entry for manually entered default pairs; automatic reverse/cross conversions.
- `screens/debt_settlement_form.dart`: native principal, account choice, conditional conversion/fee fields, date/description, projected balance and atomic partial settlement/edit/delete. Main routes principal and fee edits here.
- DebtEditor uses I owe/Owed to me, native currency choice and consistent Save text. Currency/direction lock after payments. Native phone debt actions request red/destructive styling; rendering remains OS-controlled.


Debt deadline/optional FX navigation: DebtBalanceCard missing conversions show native value and a Settings shortcut; CurrencyExchangeScreen accepts initialFrom/initialTo and opens its rate dialog with autofocus. DebtEditor includes optional deadline/date/time for liabilities and receivables. PaymentNotificationsScreen combines due debts and recurring occurrences in one lazy list, supports Keep/edit and Pay/Receive, and consumes matching native action intents. Main bell count includes due debts. RecurringNotifications schedules both sources in one bounded chronological window, using negative debt target IDs and stale-deadline payload validation. Schema 18 preserves old data with nullable deadline fields.
