# Performance notes

Measured on the Windows development host, 2026-10-31. Baseline means the working implementation immediately before this optimization pass, including the earlier Paxlee UI changes. All inputs are synthetic. These measurements describe avoided work, not phone frame rates.

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

## Reproduce and validate

```sh
flutter analyze
flutter test --concurrency=2 --dart-define=CAPTURE_UI=true
dart run tool/benchmark_ledger.dart
flutter test test/navigation_performance_test.dart --dart-define=BENCHMARK_NAVIGATION=true
flutter build apk --release
```

Validation: 181 passing tests, clean analyzer, successful release APK and checked rendered light/dark and narrow/large-text layouts. Financial, migration, recurring, receipt, bulk-selection, edge-swipe and committed-write recovery tests remain in the suite. No schema, identifiers, dependencies or financial formulas changed in this pass.

No Android device was connected. The next device check is `flutter run --profile -d <device-id>` with DevTools Performance: warm the app, switch tabs, scroll a long ledger, filter/search, then inspect slow build/raster frames. Compare the same fixture and actions before/after. Use a physical device in profile/release mode, as described by [Flutter's performance guidance](https://docs.flutter.dev/perf/ui-performance). The release artifact is `build/app/outputs/flutter-apk/app-release.apk`; the existing configuration still uses the debug signing key and is not a store-publishing setup.
