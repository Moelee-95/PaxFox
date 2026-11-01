# Performance notes

Measured on the Windows development host, 2026-10-31. Baseline means the working implementation immediately before this optimization pass, including the earlier PaxFox UI changes. All inputs are synthetic. These measurements describe avoided work, not phone frame rates.

## Changes and evidence

| Workload | Before | After |
| --- | --- | --- |
| Nine warmed main-tab switches, 5,000 entries: tracked content widget rebuilds | 108 | 0 |
| Construct snapshot index, 100,000 entries | 25.908 ms | 4.898 ms |
| 100 cycles through all four type-only filters, warmed index | 627.418 ms | 0.174 ms |
| First text search, including index construction, 100,000 entries | 29.939 ms | 30.862 ms |

The navigation test tracks HomeScreen, MonthSelector, TransactionTile, OverviewScreen and MoreScreen, after visiting all main tabs once. The shell and bottom-bar animations still rebuild as needed. It measures debug widget work, not build/raster durations. Returning to a page preserves search/scroll state; a separate assertion updates the profile while More is hidden and verifies the page receives the new data.

Calculation timings are medians of seven samples after three warmups. Both versions use the same benchmark fixture and harness. The four-filter comparison excludes first-use population; cached results reuse immutable lists until the snapshot changes. Snapshot construction is about 81% faster in this run because ordinary loading no longer lowercases every searchable string. First text search still pays that cost, so it is not claimed as faster. Timings vary with hardware, JIT/GC and host load. The existing one-pass balance and monthly/category indexes predate this pass; their benchmark speedups are not new improvements.

## Implementation

- `MainScreen` caches page widgets and scopes listeners to store, Home, filter, selection and recurring changes. `RetainedPage` keeps visited pages/controllers; inactive main pages disable tickers. Home's inner tabs also retain their scroll state.
- More, Overview account/debt cards and monthly category cards build lazily. Transaction rows use a simpler layout and static badge. A subsequent item-layout update displays the description and localized creation time inline; navigation and query optimizations remain in place.
- `LedgerIndex` lazily builds normalized text and caches type-only filters. Category lookup uses the existing map instead of scanning categories repeatedly. Icon searches cache catalog text/grouping and refilter only when the query changes.
- Category appearance-only updates skip the label-rename cascade. Actual renames, atomic snapshots, recovery and financial validation retain their previous behavior.
- Startup uses one store future and one MaterialApp. The unused legacy bottom-sheet category picker and its obsolete widget test were removed; stable-ID coverage remains in `category_icon_catalog_test.dart` and the active editor is covered by `category_form_test.dart`.

Retaining visited pages uses more memory than discarding their widgets, but long lists remain lazy. The full ledger is still loaded into memory. Very large databases may eventually need measured database pagination and background indexing; neither is introduced without a demonstrated need.

## Month navigation and loading feedback (2026-11-01)

Stored snapshots now prepare all populated month reports, category rankings and current account balances before notifying the UI. With 1,000 or more transactions, transaction decoding and this preparation run in `compute`; smaller snapshots avoid isolate startup overhead. The existing complete snapshot remains visible until preparation succeeds. Generation checks prevent an older worker result from overwriting a newer refresh. Financial formulas, ordering and persistence are unchanged.

The month pager publishes its selection when the slide ends, avoiding transaction-list layout during the title animation. Chevron slides take 180 ms, and repeated taps accumulate their destination instead of using the partially animated page. Swipes, year boundaries and external month resets remain supported.

Home's inactive inner tabs defer child updates until a tap or drag needs them. This avoids relaying out previously visited expense/income lists while the monthly report is visible; dragging prepares incoming content before it is revealed. Main destinations keep their existing live data listeners. Home transaction scrolling retains an 80px prebuild buffer, reducing offscreen card layout during month changes. `monthly_home_test` checks that hidden lists build no new rows for a month change and display current data when tapped/swiped into view.

On this host, the 100,000-entry synthetic benchmark measured first visits across 80 months (including category ranking) at **15.395 ms with lazy reports versus 1.258 ms with prepared reports**. Median full index/report preparation was **18.907 ms**, paid before navigation and in a worker for large stored snapshots. These are aggregate query timings, not frame-rate or end-to-end loading measurements. Preparing every populated month retains more report lists earlier; large-ledger worker startup/transfer also adds loading overhead. No physical-device smoothness claim is established by these numbers.

`refreshing` is a separate notifier: a global loading spinner updates without rebuilding retained page content. Save/import controls share `BusyLabel`, with visible spinners and duplicate-submit protection. Recurring checks, receipt opening/source loading, existing scan previews and pull refresh also show progress. CSV export filtering/sorting/encoding runs in a worker, matching the existing background CSV parsing.

Scanned-batch transaction IDs are cached in each complete snapshot, like legacy receipt IDs. Ordinary transaction forms no longer issue attachment queries; real attachments retain asynchronous loading/error feedback.

Regression coverage: `month_navigation_test` checks settled-only publication, rapid taps, swipes and external date changes; `loading_feedback_test` holds a real database read pending to verify animated progress without rebuilding page content, and checks disabled save controls. `ledger_queries_test` compares prepared and lazy reports across months/currencies; existing navigation, CSV, financial and recovery tests cover background snapshot compatibility.

### Isolated Android device benchmark

`tool/profile_navigation.dart` creates 24,000 synthetic transactions in an in-memory database and records engine build/raster frame timings for month changes, monthly reports and warmed main navigation. Its Android package is `de.alhayali.moneva.benchmark`, separate from the normal app. It never opens the user's database or calls Gemini. The phone must be unlocked and the benchmark app in the foreground. PowerShell build:

```powershell
Push-Location android
try {
  .\gradlew.bat assembleProfile '-PpaxfoxBenchmark=true' '-Ptarget=tool/profile_navigation.dart' '-Ptarget-platform=android-arm64' '-Pdart-defines=UEFYRk9YX0JFTkNITUFSSz10cnVl'
} finally {
  Pop-Location
}
adb install -r build/app/outputs/apk/profile/app-profile.apk
adb shell am start -n de.alhayali.moneva.benchmark/de.alhayali.moneva.MainActivity
```

The encoded Dart define above is `PAXFOX_BENCHMARK=true`. Verify the APK package with `aapt dump badging` before installation. After completion, capture the `PAXFOX_BENCHMARK` JSON line from that process's `flutter` logcat tag, then uninstall only `de.alhayali.moneva.benchmark`. The normal release build omits the Gradle property and uses the unchanged production ID and `lib/main.dart`. These measurements are synthetic and after warmup; they do not establish performance for every device or real database.

Measured on the connected **SM-S916B at 60 Hz**, in profile mode with Vulkan/Impeller and 24,000 synthetic entries over 24 months:

| Phase | Before hidden-tab/row refinement: build p95 | Final build p95 | Final raster p95 |
| --- | --- | --- | --- |
| 12 first transaction-month visits | 19.220 ms | 14.905 ms | 4.474 ms |
| 12 monthly report changes | 22.504 ms | 8.957 ms | 3.528 ms |
| 12 warmed main destination changes | 2.215 ms | 1.532 ms | 3.080 ms |

The earlier device run already included prepared reports and settled month selection; this is **not** a baseline of the original app. No new persisted user data or real app installation was used. The final transaction-month phase still had **7/153 build frames over 16.67 ms**, worst **26.436 ms**. Report changes had **0/156**, and main navigation **0/243**, over that build budget; no measured raster frame exceeded it. Full refresh took **503 ms**, including the asynchronous SQLite read, worker preparation and transfer. These single-run timings include device/load variability and should not be read as a universal smoothness guarantee. Raw local outputs: `build/smooth-device-before-hidden-tabs.log`, `build/smooth-device-profile.log`, `build/smooth-device-results.json`. The temporary benchmark package was removed after testing.

## Reproduce and validate

```sh
flutter analyze
flutter test --concurrency=2 --dart-define=CAPTURE_UI=true
dart run tool/benchmark_ledger.dart
flutter test test/navigation_performance_test.dart --dart-define=BENCHMARK_NAVIGATION=true
flutter build apk --release
```

Validation: 181 passing tests, clean analyzer, successful release APK and checked rendered light/dark and narrow/large-text layouts. Financial, migration, recurring, receipt, bulk-selection, edge-swipe and committed-write recovery tests remain in the suite. No schema, identifiers, dependencies or financial formulas changed in this pass.

No Android device was connected for the original 2026-10-31 pass. For a real-user workload, use `flutter run --profile -d <device-id>` with DevTools Performance: warm the app, switch tabs, scroll a long ledger, filter/search, then inspect slow build/raster frames. Compare the same fixture and actions before/after. Use a physical device in profile/release mode, as described by [Flutter's performance guidance](https://docs.flutter.dev/perf/ui-performance). The release artifact is `build/app/outputs/flutter-apk/app-release.apk`; the existing configuration still uses the debug signing key and is not a store-publishing setup.

Validation for the 2026-11-01 month/loading changes: **203 passing tests** with `CAPTURE_UI=true`, clean analyzer, inspected light/dark/large-text layouts and a successful normal release build. Build identity was checked as `de.alhayali.moneva` after creating the isolated benchmark package. Transaction metadata now uses one wrapping text paragraph for both labeled timestamps, avoiding a separate date paragraph and wrapping layout per row.
