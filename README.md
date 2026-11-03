# mimiTrends-iOS

This repository is the starting point for a native MiMiTrends application. iPadOS 27 is the primary development target; macOS 27 is an optional destination. The iOS app still supports iPhone. The existing Kotlin/JavaFX desktop application remains in the separate `mimiTrends` repository.

The repository, Xcode project, run scheme, and native app are named `mimiTrends-iOS`. The Kotlin/JavaFX desktop app is named MiMiTrends. The native app retains its existing bundle identifier so development installations and local data keep the same app identity.

The window title shows the app version, local build date, and compiling Mac's Computer Name. Xcode records the latter two in the app bundle during every build; the date and workstation are visible to anyone who receives that build. The Mac toolbar keeps a compact app/version badge and separate live Memory and Threads badges with bounded history graphs; sampling pauses when the scene is inactive. Hover over the app badge for the complete build title and over Memory for its compressed-memory detail.

Settings follows the prototype's Scanner, Rapid moves, Market data providers, and Appearance sections, with a separate **Color Table** pane for both radar tables. Color Table uses grouped color rows with default swatches, native color pickers, per-color restore controls, and shared table font-family and size settings with a live preview. Table colors and typography apply immediately and persist across launches. The native Scanner pane controls the saved Radar list's result count and maximum signal age; Rapid moves controls the active Finnhub detection thresholds. On Mac, Settings uses system content colours and fills the detail width with two-column groups in wide windows; narrow windows stack the groups. Provider credentials use single-line editors with show/hide buttons. iPad stores them in Keychain; Mac stores them in local app preferences to avoid repeated development-build Keychain authorization. The selected symbol, chart range, Settings section, appearance, and Radar panel sizes survive relaunches; the app always opens on Charts. See [Desktop preferences and native Settings](Docs/SettingsMigration.md) for adopted values and desktop features that are not yet active.

## Current scope

- A shared SwiftUI app target for iPad, iPhone, and Mac, with a connected iPad selected by the local command-line scripts.
- An adaptive Radar dashboard with recent saved signals, actual Finnhub feed status, and a selectable 1H, 3H, 1D, or Latest saved-minute candlestick view with EMA 9/21 and reported volume; a locally saved watchlist and a Scalable transaction CSV importer with an itemized result report.
- A radar session lifecycle hook that stops scanning whenever the app leaves the foreground.
- Shared market models for provider instruments, quotes, minute bars, and scan results.
- An XcodeGen project specification and GitHub Actions build workflow.

The app can receive Finnhub trades while it is active, save completed minute bars and detected signals, and detect close-confirmed rapid rises, crashes, liquid sustained moves, and stable intraday corridors. Radar opens first on each launch, followed by Watchlist and Settings; Charts is available below the Radar tables. The Charts tab uses [Swift Charts](https://developer.apple.com/documentation/charts/creating-a-chart-using-swift-charts) to display up to 360 saved OHLC candles, EMA 9/21, and reported trade volumes for one symbol. Move the pointer across the chart on Mac or drag across it on iPad to inspect the price and time under the crosshair. It does not fetch historical prices, fill gaps, or convert currencies. Scalable transaction CSV files can be imported from Settings; each import reports new trades by type, cancelled rows, and duplicates both within the file and already stored locally. Imports are saved in a separate native database; desktop position reconciliation and trade chart overlays remain unported. For simple US stock symbols, Radar also requests [Finnhub's separate last bid/ask endpoint](https://finnhub.io/docs/api/stock-bidask) at most once per minute and uses a fresh quote to reject poor execution prices. This endpoint may require additional account access; if the account cannot use it, trade scanning continues without bid/ask validation. European bid/ask and currency conversion remain unported; see [the porting plan](Docs/PortingPlan.md) for the source and licensing boundary. The watchlist stores symbols on this device; tapping one opens Radar with that symbol but does not start a feed. No provider credentials or production data are included.

To try the feed, enter your own Finnhub API key under **Settings → Market data providers**, then enter a symbol on Radar and tap **Start feed**. On iPad the key stays in Keychain; on Mac it stays in the app's local preferences. It can be revealed, changed, or removed in Settings. Completed minute bars are stored in the app container; the current unfinished minute is discarded when the feed stops. The feed stops when the app leaves the foreground. Availability of symbols and trade updates depends on the Finnhub account, exchange coverage, and market hours.

MiMiTrends has no live Scalable connection or account action. To import Scalable history from a file, open **Settings → Market data providers → Scalable trade history** and choose a CSV export. The importer follows the desktop semicolon-separated format, reads German decimal values and Europe/Berlin timestamps, and ignores cancelled rows and duplicate trades. The completion report lists imported buy/sell/other entries, cancelled rows, duplicates in the file, and trades already imported. Invalid files stop with a row-specific error and are not partially saved.

To view collected bars, open Charts, enter the same symbol, select a rolling 1H, 3H, or 1D range, and tap **Load chart**. Switching the range reloads it automatically. Empty periods remain empty; choose **Latest** for older saved bars. Reported trade volume is drawn only for bars whose volume status is `REPORTED`. The chart uses the source price unit; it does not claim a converted currency.

## Diagnostics

The Mac Debug build writes a bounded diagnostic log to `/tmp/mimiTrendsiOS.log` (the same file is visible as `/private/tmp/mimiTrendsiOS.log`). Run `tail -f /tmp/mimiTrendsiOS.log` while exercising Charts or Radar. The log records chart bar counts, discovery refreshes, feed connections, trade counts, and failures. It does not track Scalable account sign-in. It never records API keys or WebSocket URLs. When the file reaches 4 MB, the previous file becomes `/tmp/mimiTrendsiOS.previous.log`.

Release builds retain App Sandbox and write to their private temporary directory; the `diagnostics-ready` event in the system Console reports the exact path. On iPad and iPhone, the file is `mimiTrendsiOS.log` in the app container's `tmp` directory; for a Simulator, locate the container with `xcrun simctl get_app_container booted org.senatov.mimitrends.apple data`. Temporary logs can be removed by the OS. Review local symbols and diagnostics before sharing them.

Radar follows the desktop prototype's main visual structure: a signal list beside a source table where space permits, with a selected-symbol chart below. Drag the blue handles between panels to resize them. Wide and stacked window layouts keep separate divider positions in local device preferences and restore them after relaunch; the content scrolls when the window is too small for readable panels. Its signal list reads native saved detections, shows event badges, signed movement with its measured window, relative age, issuer-country flags, and company marks cached in a local SQLite profile database. Finnhub company profiles provide issuer country and logo when a key is configured; exchange suffixes supply a country fallback, and the prototype's domain-icon lookup fills missing logos. The Rumors button opens a recent-coverage sheet that gathers Yahoo Finance, Benzinga, and wallstreetONLINE articles for that stock, removes duplicate links, and sorts by publication date. Signal columns measure their contents, share exact widths between headings, rows, and dividers, and can be sorted numerically or alphabetically with separate heading controls. Drag a heading divider to resize a column; double-click it to restore its measured width. Source Telemetry fits its contents directly above the feed controls. Each column measures its own heading and values with the selected table font; narrow layouts scroll horizontally instead of cutting off source names or statuses. Its headings sort the source names, counters, and statuses. Yahoo minute-bar scans rotate through at most four symbols per minute and pause for 30 minutes when Yahoo returns HTTP 429. Its rows include ranking-candidate actions. Scalable does not supply live broker data to this app; the CSV importer in Settings handles exported trade history. The chart shows saved completed minutes with EMA 9/21 and reported volume. Its crosshair follows the Mac pointer or an iPad drag, snaps to the nearest saved candle, and displays the selected time and price across both plots. Latest shows at most 60 candles; timed ranges use up to 360 available bars and remain empty when no saved bars fall within the chosen period. EMA is calculated from available saved closes with the desktop smoothing rule; it cannot reconstruct missing earlier history. Preliminary LS quote movements are separate from confirmed minute-bar signals. See [Dynamic scan pool](Docs/DynamicScanPool.md) for the remaining common-pool and instrument-resolution work.

On startup, Radar immediately restores saved signals from its local database. If none fall within the configured signal-age window, it shows the most recent saved signals as **Saved radar** with the message **Older saved signals · no new confirmed signals yet**. This describes historical data, not a loading error. A progress panel covers the left table during the first market-candidate pass, reports the number of symbols checked, and prevents table actions until that pass finishes. Saved rows remain visible behind the panel. If Yahoo pauses for a rate limit or the initial scan fails, the panel closes so the saved table remains usable.

Radar and Watchlist use adaptive system content surfaces. Accent colors indicate controls or market signal meaning rather than tinting entire data panels.

The Finnhub source panel reports current-session trade receipts, completed bars saved, accepted signals, and terminal feed errors. These counts reset when a new feed starts and do not imply that other desktop providers are connected.

Radar offers **Selected** and **Selected + Watchlist** feed scopes. The second scope requests the selected ticker and up to four additional watchlist tickers matching the current Finnhub US-symbol format, in saved order. The limit bounds WebSocket subscriptions and processing; it is not the desktop's ranking-based dynamic pool. Changing scope takes effect on the next feed start. The feed still stops whenever the app leaves the foreground.

Radar loads discovery candidates from [miminavi.tech/info1](https://miminavi.tech/info1) while active. The JSON contains four 50-row periods for the aggregate performance page. The app validates generation time, attribution, instrument URLs, ranking bounds, and payload size; it deduplicates instruments, refreshes about every 30 minutes, and retains the last successful local snapshot if a refresh fails. Opening the candidate list checks up to eight visible wallstreetONLINE instrument links directly. It displays a price only when the linked page supplies a fresh EUR quote or a USD quote with a fresh EUR/USD rate from wallstreetONLINE; unconverted prices are omitted. The direct EUR observations are saved in a separate local quote database with their source currency and conversion rate. The JSON ranking prices are not shown because their currency is not declared. Ranking rows remain discovery candidates, not confirmed scanner signals or verified Finnhub symbols. See [Dynamic scan pool](Docs/DynamicScanPool.md) for remaining symbol-resolution and data-rights work.

Lang & Schwarz now has a foreground quote adapter for its Germany, STOXX 50, and Europe pages. It refreshes about every 30 seconds, accepts only fresh bid/ask rows, converts USD rows using a fresh EUR/USD quote, and saves the normalized EUR observations separately from minute trade bars. Radar displays movements over observed LS quotes as preliminary only; these pages do not supply the trade volume required by the confirmed minute-bar detectors. A failed page refresh retains prior observations for diagnostics and backs off for five minutes. Website quotes can lag executable prices and their use in a distributed app requires a separate rights review.

To save a symbol, open Watchlist, enter its ticker, and tap **Add**. Its native list shows saved symbols and their insertion dates in a card-style layout. Select a saved symbol to put it on Radar; a running feed stops before the selection changes. Use the row's trash button, or swipe the row on iPad, to delete it. These symbols stay in the app's local SQLite container and are not synchronized between devices.

## Run from the command line

Requires Xcode 27. To run on a connected iPad, enable Developer Mode on the device and configure Apple Development signing for the project team. An iPadOS 27 Simulator runtime is needed for simulator testing and CI. XcodeGen is needed only to regenerate the checked-in Xcode project (`brew install xcodegen`). Run the commands below from the repository root:

```zsh
zsh Scripts/run_ios.zsh
```

This builds, installs, and launches the app on the single paired iPad running iPadOS 27. Set `IPAD_UDID` if more than one eligible iPad is paired. To use a simulator instead, set `SIMULATOR_UDID` to an installed iPad simulator's UDID; the script then boots and launches that simulator.

All builds use this repository's ignored `DerivedData/` directory. They do not clear shared Xcode caches, modify other repositories, sign an App Store distribution binary, or upload one. Connected-iPad builds use the configured Apple Development team; simulator builds use local ad hoc signing so Keychain works during development. On Mac, the app attempts a single silent import of existing Keychain values into local preferences. If macOS denies that read, re-enter the value once in Settings; no Keychain password dialog is requested. The generated Xcode project is committed so it can also be opened directly in Xcode.

## Scripts and macOS release

Run these commands from the repository root. `Scripts/_common.zsh` supplies the shared project paths and selects an eligible iPad or simulator. The scripts use the generated `mimiTrends-iOS.xcodeproj`; `mimiTrendsIOS.xcodeproj` is retained for older local Xcode setups and is kept at the same release version.

| Script | What it does and when to use it |
| --- | --- |
| `_common.zsh` | Internal helper sourced by the other shell scripts; checks Xcode and the project, selects a paired iPad or iPadOS 27 simulator, and boots a simulator when needed. Do not run it on its own. |
| `generate_project.zsh` | Regenerates the canonical Xcode project from `project.yml` after source files or project settings change. CI runs it before building. Requires XcodeGen. |
| `build_ios.zsh` | Builds for a paired iPad with Apple Development signing; `Release` selects the Release configuration. `SIMULATOR_UDID` or `CI=true` selects an ad hoc signed simulator build. It does not install the app. |
| `run_ios.zsh` | Builds, installs, and launches on the selected iPad; with `SIMULATOR_UDID`, boots and uses that simulator. Use it to check the running iPad UI. |
| `test_ios.zsh` | Runs the native XCTest suite on the selected iPad or simulator. CI uses a simulator. |
| `build_macos.zsh` | Builds an unsigned Mac app in Debug or `Release`. Use it for compilation checks; an unsigned build is not a distributable DMG. |
| `run_macos.zsh` | Stops this checkout's existing Mac app, builds Debug, signs it with the local Developer ID identity and sandbox entitlements, then launches and checks the app process. Requires macOS 27 and a matching signing identity. |
| `check_macos_sandbox.zsh` | Checks the entitlement plist and **Release** Mac build settings for sandbox, outbound network, selected-file read access, bundle ID, and product name. It checks configuration, not runtime permissions. |
| `write_build_info.zsh` | Xcode build phase, run automatically, that writes build date and the compiling Mac's Computer Name into `BuildInfo.plist` for the window title. |
| `release_version.py` | Internal release helper that validates four single-digit version components, calculates carry after 9, and synchronizes `MARKETING_VERSION` and numeric build version in `project.yml` and both checked-in projects. `current` and `next` are available for inspection. |
| `release_macos.zsh` | On a clean `main`, calculates the next version, regenerates the project, builds and Developer ID signs Release with hardened runtime, creates a DMG, submits it to Apple, staples and verifies it, then commits the version, pushes its matching tag, and publishes the DMG as a GitHub Release. `--dry-run` only reports the next version. |

Examples:

```zsh
zsh Scripts/generate_project.zsh
SIMULATOR_UDID=YOUR_IPAD_SIMULATOR_UDID zsh Scripts/test_ios.zsh
zsh Scripts/build_macos.zsh Release
zsh Scripts/check_macos_sandbox.zsh
zsh Scripts/release_macos.zsh --dry-run
zsh Scripts/release_macos.zsh
```

The release script requires Xcode, XcodeGen, an authenticated GitHub CLI, a Developer ID Application certificate for the team in `project.yml`, and a usable `notarytool` Keychain profile. It uses this Mac's existing `MiMiNotary` profile by default and checks access before building; set `MIMITRENDS_NOTARY_PROFILE` only to use a different profile. Apple's [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) explains how profiles are stored; credentials stay in Keychain. `MIMITRENDS_MAC_SIGN_IDENTITY` can select a different installed identity for the same team. The version and GitHub Release title use exactly `0.0.0.0`: the current source version is `0.0.1.1`, so the first release from it will be `0.0.1.2`; `0.0.1.9` advances to `0.0.2.0`. The script also considers existing tags and releases, refuses to wrap after `9.9.9.9`, and stops before publication if signing, notarization, stapling, or verification fails. DMGs and notarization results stay under ignored `DerivedData/Releases/`.

## App Store preparation

The current app is a development skeleton and is **not ready for App Review**: position reconciliation, broader scanner behavior, and provider data rights remain incomplete; Scalable CSV transaction import is available in Settings. Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) require a complete, useful app, and the Mac App Store also requires sandboxing and Xcode-based packaging.

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
4. Complete position reconciliation and signal linking for imported Scalable trades.
5. Validate signed iOS and macOS archives, provider data rights, privacy disclosures, and sandbox behavior before App Store submission.

Scanning runs only while the app is active. `MiMiTrendsApp` stops the radar session when the scene becomes inactive or enters the background, cancelling the current Finnhub subscriptions and scan task.
