# mimiTrends-iOS

This repository is the starting point for a native MiMiTrends application. iPadOS 27 is the primary development target; macOS 27 is an optional destination. The iOS app still supports iPhone. The existing Kotlin/JavaFX desktop application remains in the separate `mimiTrends` repository.

The repository, Xcode project, run scheme, and native app are named `mimiTrends-iOS`. The Kotlin/JavaFX desktop app is named MiMiTrends. The native app retains its existing bundle identifier so development installations and local data keep the same app identity.

The window title shows the app version, local build date, and compiling Mac's Computer Name. Xcode records the latter two in the app bundle during every build; the date and workstation are visible to anyone who receives that build. The Mac toolbar keeps a compact app/version badge and separate live Memory and Threads badges with bounded history graphs; sampling pauses when the scene is inactive. Hover over the app badge for the complete build title and over Memory for its compressed-memory detail.

Settings follows the prototype's Scanner, Rapid moves, Market data providers, and Appearance sections. The native Scanner pane controls the saved Radar list's result count and maximum signal age; Rapid moves controls the active Finnhub detection thresholds. On Mac, Settings uses system content colours and fills the detail width with two-column groups in wide windows; narrow windows stack the groups. Provider credentials use single-line editors with show/hide buttons. iPad stores them in Keychain; Mac stores them in local app preferences to avoid repeated development-build Keychain authorization. The selected symbol, chart range, Settings section, appearance, and Radar panel sizes survive relaunches; the app always opens on Charts. See [Desktop preferences and native Settings](Docs/SettingsMigration.md) for adopted values and desktop features that are not yet active.

## Current scope

- A shared SwiftUI app target for iPad, iPhone, and Mac, with a connected iPad selected by the local command-line scripts.
- An adaptive Radar dashboard with recent saved signals, actual Finnhub feed status, and a selectable 1H, 3H, 1D, or Latest saved-minute candlestick view with EMA 9/21 and reported volume; a full Charts tab, a locally saved watchlist with desktop snapshot import, and a local API key setting.
- A radar session lifecycle hook that stops scanning whenever the app leaves the foreground.
- Shared market models for provider instruments, quotes, minute bars, and scan results.
- An XcodeGen project specification and GitHub Actions build workflow.

The app can receive Finnhub trades while it is active, save completed minute bars and detected signals, and detect close-confirmed rapid rises, crashes, liquid sustained moves, and stable intraday corridors. Charts opens first on each launch, followed by Radar, Watchlist, and Settings. The Charts tab uses [Swift Charts](https://developer.apple.com/documentation/charts/creating-a-chart-using-swift-charts) to display up to 360 saved OHLC candles, EMA 9/21, and reported trade volumes for one symbol. It does not fetch historical prices, fill gaps, or convert currencies. A bounded snapshot of one symbol's desktop bars can be imported into the chart. For simple US stock symbols, Radar also requests [Finnhub's separate last bid/ask endpoint](https://finnhub.io/docs/api/stock-bidask) at most once per minute and uses a fresh quote to reject poor execution prices. This endpoint may require additional account access; if the account cannot use it, trade scanning continues without bid/ask validation. European bid/ask and currency conversion remain unported; see [the porting plan](Docs/PortingPlan.md) for the source and licensing boundary. The watchlist stores symbols on this device; tapping one opens Radar with that symbol but does not start a feed. The full desktop scanner and broker import remain unported. No provider credentials or production data are included.

To try the feed, enter your own Finnhub API key under **Settings → Market data providers**, then enter a symbol on Radar and tap **Start feed**. On iPad the key stays in Keychain; on Mac it stays in the app's local preferences. It can be revealed, changed, or removed in Settings. The same screen stores a Finnhub webhook secret or additional named keys and tokens for future adapters; those entries are not used by the current feed. Completed minute bars are stored in the app container; the current unfinished minute is discarded when the feed stops. The feed stops when the app leaves the foreground. Availability of symbols and trade updates depends on the Finnhub account, exchange coverage, and market hours.

To view collected bars, open Charts, enter the same symbol, select a rolling 1H, 3H, or 1D range, and tap **Load chart**. Switching the range reloads it automatically. Empty periods remain empty; choose **Latest** for older imported bars. Reported trade volume is drawn only for bars whose volume status is `REPORTED`. The chart uses the source price unit; it does not claim a converted currency.

## Diagnostics

The Mac Debug build writes a bounded diagnostic log to `/tmp/mimiTrends-iOS.log` (the same file is visible as `/private/tmp/mimiTrends-iOS.log`). Run `tail -f /tmp/mimiTrends-iOS.log` while exercising Charts or Radar. The log records chart bar counts, discovery refreshes, feed connection and trade counts, and failures. It never records API keys or WebSocket URLs. When the file reaches 4 MB, the previous file becomes `/tmp/mimiTrends-iOS.previous.log`.

Release builds retain App Sandbox and write to their private temporary directory; the `diagnostics-ready` event in the system Console reports the exact path. On iPad and iPhone, the file is `mimiTrends-iOS.log` in the app container's `tmp` directory; for a Simulator, locate the container with `xcrun simctl get_app_container booted org.senatov.mimitrends.apple data`. Temporary logs can be removed by the OS. Review local symbols and diagnostics before sharing them.

Radar now follows the desktop prototype's main visual structure: a signal list beside a source table where space permits, with a selected-symbol chart below. Drag the blue handles between panels to resize them. Wide and stacked window layouts keep separate divider positions in local device preferences and restore them after relaunch; the content scrolls when the window is too small for readable panels. Its signal list reads native saved detections, shows event badges, signed movement with its measured window, relative age, and a stronger rapid-crash row treatment. The source table reports only the real Finnhub connection, last trade age, and session trade count; the chart shows saved completed minutes with EMA 9/21 and reported volume. Latest shows at most 60 candles; timed ranges use up to 360 available bars and remain empty when no saved bars fall within the chosen period. EMA is calculated from available saved closes with the desktop smoothing rule; it cannot reconstruct missing earlier history. It does not claim the desktop's multi-provider coverage or continuous multi-symbol scanning. See [Dynamic scan pool](Docs/DynamicScanPool.md) for the prototype's ranking discovery and 30-minute pool refresh design, which the native app still needs to implement.

Charts, Radar, and Watchlist use adaptive system content surfaces. Accent colors indicate controls or market signal meaning rather than tinting entire data panels.

The Finnhub source panel reports current-session trade receipts, completed bars saved, accepted signals, and terminal feed errors. These counts reset when a new feed starts and do not imply that other desktop providers are connected.

Radar offers **Selected** and **Selected + Watchlist** feed scopes. The second scope requests the selected ticker and up to four additional watchlist tickers matching the current Finnhub US-symbol format, in saved order. The limit bounds WebSocket subscriptions and processing; it is not the desktop's ranking-based dynamic pool. Changing scope takes effect on the next feed start. The feed still stops whenever the app leaves the foreground.

Radar now loads discovery candidates from [miminavi.tech/info1](https://miminavi.tech/info1) while the app is active. The JSON contains four 50-row periods for the aggregate performance page. The app validates the generation time, source-page attribution, instrument URLs, ranking bounds, and payload size; it deduplicates instruments, refreshes about every 30 minutes, and retains the last successful local snapshot if a refresh fails. The source panel distinguishes a current fetch from a saved snapshot. When there are no confirmed scanner signals, Radar shows the published one-day leaders with source price and percentage change; the complete candidate list shows those values as well. These rows are discovery candidates only: the JSON provides website instrument links, not verified Finnhub tickers, so the app does not subscribe to or scan them yet. The separate catalog for DAX, CDAX, MDAX, TecDAX, SDAX, Eurozone 50, US 30, US Tech 100, US 500, and Trending Stocks is still a model for later source coverage. See [Dynamic scan pool](Docs/DynamicScanPool.md) for the remaining symbol-resolution and data-rights work.

To save a symbol, open Watchlist, enter its ticker, and tap **Add**. Its native list shows saved symbols and their insertion dates in a card-style layout. Select a saved symbol to put it on Radar; a running feed stops before the selection changes. Use the row's trash button, or swipe the row on iPad, to delete it. These symbols stay in the app's local SQLite container and are not synchronized between devices.

To transfer the desktop watchlist, create a small snapshot on the desktop Mac:

```zsh
python3 Scripts/export_desktop_watchlist.py ~/Desktop/watchlist.json
```

The script opens `~/.mimi/trends/mimitrends.db` read-only and exports only the ordered `user_watchlist` symbols and insertion times, with a 500-entry limit. It creates a new file without overwriting an existing one; `--source /path/to/mimitrends.db` selects another database. Transfer the JSON file with Files or AirDrop, then choose **Import desktop watchlist** in the native Watchlist tab. The import validates the complete snapshot, adds missing symbols transactionally, and keeps existing native entries and their insertion times. The snapshot contains no credentials, broker data, or market history.

To bring a small part of the desktop history to iPad or Mac, first create a snapshot on the desktop Mac:

```zsh
python3 Scripts/export_desktop_bars.py AAPL ~/Desktop/AAPL-bars.sqlite
```

The script opens `~/.mimi/trends/mimitrends.db` read-only, selects at most the latest 360 completed bars for one symbol in a consistent SQLite read transaction, and creates a new file without overwriting an existing one. Pass `--source /path/to/mimitrends.db` to choose another desktop database. Transfer the resulting `.sqlite` file to the device using Files or AirDrop, then choose **Import desktop snapshot** on Radar's chart. The app verifies the snapshot and imports it transactionally; choose **Latest** to view saved bars even when they are older than 24 hours. Do not select the live desktop `mimitrends.db` in the app. Broker trades, settings, credentials, and other desktop tables are never included in this export.

## Run from the command line

Requires Xcode 27. To run on a connected iPad, enable Developer Mode on the device and configure Apple Development signing for the project team. An iPadOS 27 Simulator runtime is needed for simulator testing and CI. XcodeGen is needed only to regenerate the checked-in Xcode project (`brew install xcodegen`). Run the commands below from the repository root:

```zsh
zsh Scripts/run_ios.zsh
```

This builds, installs, and launches the app on the single paired iPad running iPadOS 27. Set `IPAD_UDID` if more than one eligible iPad is paired. To use a simulator instead, set `SIMULATOR_UDID` to an installed iPad simulator's UDID; the script then boots and launches that simulator.

| Script | Purpose |
| --- | --- |
| `zsh Scripts/generate_project.zsh` | Regenerate `mimiTrends-iOS.xcodeproj` from `project.yml` after changing project settings or files. |
| `zsh Scripts/build_ios.zsh` | Build a development-signed app for the connected iPad. Pass `Release` for a Release configuration build. With `SIMULATOR_UDID` or `CI=true`, build an ad hoc signed simulator app instead. |
| `zsh Scripts/run_ios.zsh` | Build, install, and launch on the connected iPad. Set `SIMULATOR_UDID` to use an iPad simulator. |
| `zsh Scripts/test_ios.zsh` | Run unit tests on the connected iPad. With `SIMULATOR_UDID` or `CI=true`, use an iPad simulator. |
| `zsh Scripts/build_macos.zsh` | Build the optional unsigned macOS app. Pass `Release` for a Release configuration build. |
| `zsh Scripts/run_macos.zsh` | Stop the existing app from this checkout, build, sign with this Mac's stable Developer ID Application identity and the Mac App Sandbox entitlements, then launch one `mimiTrends-iOS.app` instance on macOS 27 or newer; verify its path, bundle ID, display name, and PID. Set `MIMITRENDS_MAC_SIGN_IDENTITY` to select another installed identity for the configured team. |
| `zsh Scripts/check_macos_sandbox.zsh` | Check the Mac target's sandbox entitlement file and Xcode build settings. |
| `Scripts/write_build_info.zsh` | Xcode build phase that records the local build date and compiling Mac's Computer Name in the app bundle for the window title. It runs automatically during each app build. |
| `python3 Scripts/export_desktop_bars.py SYMBOL OUTPUT` | Create a read-only, bounded minute-bar snapshot for one symbol from the desktop SQLite database. |
| `python3 Scripts/export_desktop_watchlist.py OUTPUT` | Export up to 500 desktop watchlist symbols to a new JSON file for native import. |

All builds use this repository's ignored `DerivedData/` directory. They do not clear shared Xcode caches, modify other repositories, sign an App Store distribution binary, or upload one. Connected-iPad builds use the configured Apple Development team; simulator builds use local ad hoc signing so Keychain works during development. On Mac, the app attempts a single silent import of existing Keychain values into local preferences. If macOS denies that read, re-enter the value once in Settings; no Keychain password dialog is requested. The generated Xcode project is committed so it can also be opened directly in Xcode.

## App Store preparation

The current app is a development skeleton and is **not ready for App Review**: desktop watchlist migration, broker imports, broader scanner behavior, and provider data rights remain incomplete. Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) require a complete, useful app, and the Mac App Store also requires sandboxing and Xcode-based packaging.

- The macOS Release target uses [App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox) with outgoing network access and read-only access to user-selected import files. It requests no unrestricted folder or incoming network access. The local Mac Debug build omits sandboxing so its diagnostic log can use `/tmp`; test Release separately for sandbox behavior. See [Storage and desktop data migration](Docs/DataStorage.md) for the planned container layout and migration rules.
- The iOS and macOS apps use SwiftUI and system APIs; the former JVM/JavaFX runtime is not bundled.
- The native app uses `org.senatov.mimitrends.apple` on both platforms so it can coexist with the existing macOS JVM app.
- The scripts produce local iPad, simulator, and Mac development builds. For App Store distribution, archive with Xcode, validate the archive, and submit through App Store Connect. Development and local ad hoc signing are not evidence of App Store approval. See Apple's [distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases).
- Before submission, complete the market features, confirm that the Finnhub agreement permits the intended App Store distribution and display of market data, review privacy disclosures, test on supported devices, and provide any account or demo access required for review. [Finnhub lists commercial use and redistribution rights separately](https://api.finnhub.io/pricing-startups-and-enterprise) from personal-use plans; a user-supplied API key does not itself establish distribution rights.

## Next implementation stages

Progress and completion gates are tracked in [the porting plan](Docs/PortingPlan.md).

1. Define shared models for instruments, quotes, and signals, with tests against representative desktop outputs.
2. Port one provider adapter and its decoding, with secure credential storage where applicable.
3. Port scanner rules and SQLite persistence incrementally.
4. Build adaptive radar and chart views, then add watchlists and broker imports.
5. Validate signed iOS and macOS archives, provider data rights, privacy disclosures, and sandbox behavior before App Store submission.

Scanning runs only while the app is active. `MiMiTrendsApp` stops the radar session when the scene becomes inactive or enters the background, cancelling the current Finnhub subscriptions and scan task.
