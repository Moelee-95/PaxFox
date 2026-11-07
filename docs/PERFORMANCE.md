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

## Reusable sheets (2026-11-01)

Category selection uses a lazy grid backed by the indexed category query. The 250-category regression test mounts fewer than 40 tappable cells initially. Shared entry editors bind text controllers directly instead of rebuilding the whole sheet on each keystroke, retain field identity across keyboard layout changes, and keep Save above the keyboard. These are structural improvements verified by widget tests, not new physical-device frame-time measurements. All 210 tests pass; analyzer and release build are clean.

The Categories management screen also uses indexed per-kind lists and lazy card construction. The 250-category regression checks fewer than 25 mounted management rows, while retaining the picker grid limit. Expense/income tabs keep separate scroll positions; category edits use the existing transactional save path.

## More/Cashflow freeze investigation (2026-11-01)

The connected SM-S916B Android ANR at 15:52:45 came from a debug build. Symbolizing its engine stack with the matching debug symbols showed `dart::Isolate::PauseEventHandler`, `dart::Debugger::PauseException` and `dart::ThrowExceptionHelper` on the merged platform/UI thread; raster and SQLite threads were idle. This establishes a debugger exception pause, not a measured slow ledger query. The original Dart exception text was unavailable. After restarting the same debug build, repeated slow/fast More-to-Cashflow swipes did not reproduce a pause, including a VM-service Debug subscription with exception pausing enabled. A new widget regression checks repeated swipes and navigation taps interrupting partial drags; it passes without changing navigation behavior.

The final production-ID release update preserved the installed data. Twenty More-to-Cashflow swipe cycles followed by a Home tap completed on the phone; Home rendered normally and Android last-ANR remained the original 15:52:45 event. This does not identify the original Dart exception or establish a general no-freeze guarantee. Local evidence: build/freeze-anr.txt, build/freeze-probe.log, build/outline-phone-home.png.

## Monthly savings chart (2026-11-01)

The reusable FL Chart card requests only the six visible existing monthly reports. Totals are already prepared/cached per snapshot, so touch selection and range navigation do not iterate the full ledger. Only the chart's local state rebuilds for touch selection; a repaint boundary isolates its paint work. Animations last 180ms and respect the system disable-animations setting. No new snapshot preprocessing, database query or persisted cache was introduced. These are structural bounds, not a new device frame-time benchmark.

The denser chart revision always draws six months and uses FL Chart's native rod labels for permanent amounts (including zero/negative values). Redundant y-axis labels were removed so all six bar/month columns share the available width. Dense plot/month text caps scaling at 1.15 to keep columns legible; the exact-value summary retains the user's full text scaling. No additional report queries or canvas layers were added.


## Invoice image preparation (2026-11-06)

The former mobile path sampled with Flutter's codec, encoded a PNG intermediate, decoded that PNG in Dart, then encoded JPEG up to three times. It allowed 12 MP panoramas and decoded even already suitable small JPEGs. A timeout/cancel discarded UI results but left processing running, so retries could overlap that work.

Android now samples with BitmapFactory before allocating pixels, applies EXIF orientation and performs one native JPEG encode on a background executor. The executor retires with its Flutter engine. iOS uses ImageIO thumbnail decoding with orientation transform and one JPEG encode on a serial queue. Both enforce a 4 MP output budget, 2,000px short edge and 6,000px long edge, without upscaling. Compatible unrotated JPEGs <=1 MiB bypass pixel decoding. A Dart queue serializes preparation across retries and extraction; canceled generations skip pending work and discard active results before writing. Picker-owned source files remain until their preparation settles. The 45-second watchdog still handles broken/stalled file or OS operations; it does not enforce CPU cancellation inside an OS decoder.

Synthetic measurements on the connected SM-S916B (Android 17), isolated `de.alhayali.moneva.benchmark` package:

| Synthetic source | Old release | Native release | Native debug |
| --- | --- | --- | --- |
| 8 MP gray detail | 3,468 ms | 253 ms | 201 ms |
| 12 MP gray detail | 5,065 ms | 233 ms | 302 ms |
| 12 MP EXIF-rotated | 5,954 ms | 253 ms | 349 ms |
| 12 MP panorama | 4,441 ms | 341 ms | 293 ms |

Native runs also checked a 500x700 JPEG remained byte-identical, output pixel bounds, EXIF rotation/aspect ratio, JPEG format, source preservation and cached-byte identity. The old panorama produced a 6.43 MB/12 MP upload; the new one is 3,464x1,154 (<4 MP). Cached reads avoid further image processing. An explicit legacy debug replica took 5,352 ms for the 12 MP photo. The reported 45-second failure was not reproduced on this device; these measurements demonstrate removal of the costly stages, not a guarantee for every file/device. iOS native build/runtime checks require macOS/Xcode and remain unverified.

`tool/profile_invoice_preparation.dart` creates only synthetic temporary images and never opens the ledger or calls Gemini. From `android/`, build its isolated APK with:

```powershell
.\gradlew.bat assembleRelease '-PpaxfoxBenchmark=true' '-Ptarget=tool/profile_invoice_preparation.dart' '-Ptarget-platform=android-arm64' '-Pdart-defines=UEFYRk9YX0JFTkNITUFSSz10cnVl'
```

Use `assembleDebug` to include the legacy comparison; that comparison uses a separately killable isolate with a two-minute bound. Verify the APK package ID before installing and remove only the benchmark package afterward. Per-fixture `PAXFOX_IMAGE_RESULT` logs are authoritative because Android may truncate the aggregate JSON line. Local results/logs: `build/image-benchmark-baseline-results.json`, `build/image-benchmark-native-release-results.json`, `build/image-benchmark-native-debug-results.json`, `build/image-benchmark-legacy-debug-results.json` and matching device logs. The benchmark package was removed; the production app/database were untouched.

Validation: 11 image-preparation tests and 7 scanner tests pass, including strict pixel rounding, cancellation/retry serialization, stale queued job skipping, source preservation and cache reuse. Analyzer clean. Full suite: 220 passed, with the previously observed unrelated category-screen large-text ListTile layout failure in `bottom_sheets_test.dart`.
