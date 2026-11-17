# mimiTrends-iOS

**macOS download:** [Latest release and notarized DMG](https://github.com/senatov/mimiTrendsIOS/releases/latest) · [All releases](https://github.com/senatov/mimiTrendsIOS/releases). Open the latest release and expand **Assets** to find the DMG. The Mac build requires macOS 27 or newer; the iPad App Store build is not published yet.

This repository is the starting point for a native MiMiTrends application. iPadOS 27 is the primary development target; macOS 27 is an optional destination. The iOS app still supports iPhone. The existing Kotlin/JavaFX desktop application remains in the separate `mimiTrends` repository.

The repository, Xcode project, run scheme, and native app are named `mimiTrends-iOS`. The Kotlin/JavaFX desktop app is named MiMiTrends. The native app retains its existing bundle identifier so development installations and local data keep the same app identity.

The window title shows the app version, local build date, and compiling Mac's Computer Name. Xcode records the latter two in the app bundle during every build; the date and workstation are visible to anyone who receives that build. The Mac toolbar keeps a compact app/version badge and separate live Memory and Threads badges with bounded history graphs; sampling pauses when the scene is inactive. Hover over the app badge for the complete build title and over Memory for its compressed-memory detail.

Settings includes Scanner, Rapid moves, Market data providers, Appearance, and Color Table. Radar scans fresh Yahoo minute candles with reported volume; it does not require a provider account. The selected symbol, chart range, Settings section, appearance, and Radar panel sizes survive relaunches.

## Current scope

- A shared SwiftUI app target for iPad, iPhone, and Mac, with a connected iPad selected by the local command-line scripts.
- An adaptive Radar dashboard with recent candle signals, source status, a selectable minute-candle chart, a local watchlist, and a Scalable transaction CSV importer.
- A radar session lifecycle hook that stops scanning whenever the app leaves the foreground.
- Shared market models for provider instruments, quotes, minute bars, and scan results.
- An XcodeGen project specification and GitHub Actions build workflow.

While the app is active, Radar scans a pool of up to 255 US and German shares selected from TradingView activity and volatility rankings and observed in the public EIX pre-trade file. It uses completed Yahoo minute candles and reported volume to detect rapid drops, confirmed reversals, and sustained rises. Candidates without a matching EIX ISIN are skipped before the pool is capped, allowing the next eligible shares to take their places. The chart displays saved minute candles and daily summaries with EMA 9/21 and reported volume. The app also monitors boerse.de price movements and keeps Lang & Schwarz quotes separate from candle signals. Scalable CSV trades are stored in their own database.

Open Radar during market hours to scan automatically. No API key or webhook secret is required.



Radar's default rapid-move profile detects a rise or drop of at least 0.8% within five minutes, subject to reported-volume and turnover checks. A longer drop rule uses 2% within 15 minutes and additional checks. The newest signals appear first by default; column controls can change the order. Adjust these values under **Settings → Rapid moves**. A signal describes a completed move and can be delayed by the data source; it does not predict the next price.

At the US market open, the first two completed regular-session bars can confirm a drop from prices in the preceding five premarket minutes when both opening bars have reported volume. Radar rechecks the selected symbol and the first three scan candidates about once a minute, and can retain a qualifying drop from the preceding three minutes if the price remains below its earlier high. Signals keep the candle's event time; Yahoo publication and request time still affect when they appear.

MiMiTrends has no live Scalable connection or account action. EIX membership is an exchange-data check, not a guarantee that a security can be bought through Scalable or that a quote is currently executable. To import Scalable history from a file, open **Settings → Market data providers → Scalable trade history** and choose a CSV export. The importer follows the desktop semicolon-separated format, reads German decimal values and Europe/Berlin timestamps, and ignores cancelled rows and duplicate trades. The completion report lists imported buy/sell/other entries, cancelled rows, duplicates in the file, and trades already imported. Invalid files stop with a row-specific error and are not partially saved.

The chart loads saved Yahoo minute bars for intraday ranges and summarizes them by trading date for 1W and 1Y. Reported volume is drawn only for bars with reported volume. Prices are converted for display when ECB reference rates are available.

Radar is designed to be approachable for people new to market terminology: each signal appears with the measured price move and time window, and the table explains how to read those values in plain language. Signals describe recent activity; they are not forecasts or buy/sell instructions.

## Diagnostics

The Mac Debug build writes a bounded diagnostic log to `/tmp/mimiTrendsiOS.log` (the same file is visible as `/private/tmp/mimiTrendsiOS.log`). Run `tail -f /tmp/mimiTrendsiOS.log` while exercising Charts or Radar. The log records chart bar counts, discovery refreshes, scanner progress, and failures. It does not track Scalable account sign-in. It never records credentials. When the file reaches 4 MB, the previous file becomes `/tmp/mimiTrendsiOS.previous.log`.

Release builds retain App Sandbox and write to their private temporary directory; the `diagnostics-ready` event in the system Console reports the exact path. On iPad and iPhone, the file is `mimiTrendsiOS.log` in the app container's `tmp` directory; for a Simulator, locate the container with `xcrun simctl get_app_container booted org.senatov.mimitrends.apple data`. Temporary logs can be removed by the OS. Review local symbols and diagnostics before sharing them.

Radar gives the signal list the main width and places the selected-symbol chart below. Sources shows TradingView candidate discovery, Yahoo candle scanning, Lang & Schwarz quote status, and the EIX-filtered candidate list. Saved signals remain in local history but appear in Radar only when their symbol is in the current TradingView candidate set and its ISIN occurs in the EIX file. Company names are resolved from candle metadata when ranking pages provide only a ticker. The Rumors sheet gathers ticker-specific Yahoo Finance news, with Benzinga and wallstreetONLINE coverage where available; each item keeps its publisher and article link. News is sorted newest first and duplicate links are removed.

**Display currency:** On first launch, the app asks an HTTPS IP-country service for the public IP country and selects its currency when it is among the 30 currencies supported by the European Central Bank (ECB) reference feed; otherwise it starts in EUR. It does not request GPS or device-location permission. Choose another currency at any time under **Settings → Currency**. The choice is saved. Radar signal prices, ranking-candidate quotes, chart candles and EMA lines, chart inspection values, and imported trade overlays display in that currency. The app fetches the ECB daily XML reference rates, caches them locally for up to seven days, and labels approximate conversions with the ECB rate date. Prices and bars remain in their source currencies in storage. If a necessary rate is unavailable, the affected display shows a dash or waits for rates rather than silently showing a different currency. These conversions are informational and are not quotes on a local exchange.

On startup, Radar loads saved signals from its local database, then displays only those that pass the current EIX and candidate check. The table can remain empty until the EIX file and TradingView candidates have loaded. When a visible saved signal row appears, an asynchronous task checks for that symbol's minute bars in SQLite and requests Yahoo bars only when none are stored, with a 15-minute retry limit and shared rate-limit cooldown. Independent candidate discovery continues in the background so an empty signal list can still gain new detections. Its full 16-symbol pass is spread across minute-spaced batches to limit Yahoo requests, and source telemetry reports its provider status without a startup progress panel.


Radar and its watchlist editor use adaptive system content surfaces. Accent colors indicate controls or market signal meaning rather than tinting entire data panels.



Radar refreshes its TradingView candidates at startup and about every 10 minutes while the app is active. It requests TradingView's Germany and USA activity and volatility screeners, restricts the results to Xetra, NASDAQ, NYSE and NYSE American shares with Yahoo-compatible symbols, and requires a price of at least 5 and market capitalization of at least 100 million in the market currency. German shares need daily traded value of at least 500,000 EUR; US shares need at least 1 million USD. Volatility candidates additionally need daily volatility of at least 1% and relative volume of at least 0.5 for Germany or 0.2 for the US. The app also reads the newest day's opening [EIX pre-trade file](https://european-investor-exchange.com/de/pretrade) and matches candidates by ISIN. Up to 96 active US shares and 64 active German shares take priority; volatility candidates fill the remaining slots in a deduplicated pool of at most 255 symbols. The EIX set refreshes hourly and its last successful snapshot remains usable for up to 48 hours; a failed request retries after five minutes. If no valid EIX set is available, no candidates or saved signals are shown. The public pre-trade file is a conservative observation set rather than a complete broker catalogue: a missing ISIN does not prove that Scalable or another venue cannot trade the share. If the volatility screener is unavailable, Radar reads the first 100 rows of each configured volatility page, but rows without an ISIN cannot pass the EIX check. A failed TradingView refresh retains the last successful list for up to one day and retries after one minute. Yahoo minute candles and reported volume confirm signals. German candidates enter the candle scan during the regular Xetra session, while US candidates are eligible during premarket, regular trading and after-hours. The two TradingView page URLs can be checked and edited under provider settings as volatility fallbacks.

TradingView's terms restrict automated data collection, including page parsing and undocumented endpoints. Confirm the intended access and data-use rights before distributing this build.

Lang & Schwarz now has a foreground quote adapter for its Germany, STOXX 50, and Europe pages. It refreshes about every 30 seconds, accepts only fresh bid/ask rows, converts USD rows using a fresh EUR/USD quote, and saves the normalized EUR observations separately from minute trade bars. Radar keeps these quotes in source telemetry and separate local quote storage; these pages do not supply the trade volume required by the confirmed minute-bar detectors, so their price movements are not shown as signals. A failed page refresh retains prior observations for diagnostics and backs off for five minutes. Website quotes can lag executable prices and their use in a distributed app requires a separate rights review.

To save a symbol, tap **Edit watchlist** in Radar, enter its ticker, and tap **Add**. The watchlist sheet shows saved symbols and their insertion dates. Use a row's pencil button to correct its ticker without changing its saved order. Select a saved symbol to put it on Radar; Use the row's trash button, or swipe the row on iPad, to delete it. These symbols stay in the app's local SQLite container and are not synchronized between devices.

## Run from the command line

Requires Xcode 27. To run on a connected iPad, enable Developer Mode on the device and configure Apple Development signing for the project team. An iPadOS 27 Simulator runtime is needed for simulator testing and CI. XcodeGen is needed only to regenerate the checked-in Xcode project (`brew install xcodegen`). Run the commands below from the repository root:

```zsh
zsh Scripts/run_ios.zsh
```

This builds, installs, and launches the app on the single paired iPad running iPadOS 27. Set `IPAD_UDID` if more than one eligible iPad is paired. To use a simulator instead, set `SIMULATOR_UDID` to an installed iPad simulator's UDID; the script then boots and launches that simulator.

All builds use this repository's ignored `DerivedData/` directory. They do not clear shared Xcode caches, modify other repositories, sign an App Store distribution binary, or upload one. Connected-iPad builds use the configured Apple Development team; simulator builds use local ad hoc signing so Keychain works during development. The generated Xcode project is committed so it can also be opened directly in Xcode.

## Scripts and macOS release

Run these commands from the repository root. `Scripts/_common.zsh` supplies the shared project paths and selects an eligible iPad or simulator. The scripts use the single generated `mimiTrends-iOS.xcodeproj`. Regenerate it through `Scripts/generate_project.zsh` after adding source files.

| Script | What it does and when to use it |
| --- | --- |
| `_common.zsh` | Internal helper sourced by the other shell scripts; checks Xcode and the project, selects a paired iPad or iPadOS 27 simulator, and boots a simulator when needed. Do not run it on its own. |
| `generate_project.zsh` | Regenerates the canonical Xcode project from `project.yml` and mirrors it into the legacy project after source files or project settings change. CI runs it before building. Requires XcodeGen. |
| `build_ios.zsh` | Builds for a paired iPad with Apple Development signing; `Release` selects the Release configuration. `SIMULATOR_UDID` or `CI=true` selects an ad hoc signed simulator build. It does not install the app. |
| `run_ios.zsh` | Builds, installs, and launches on the selected iPad; with `SIMULATOR_UDID`, boots and uses that simulator. Use it to check the running iPad UI. |
| `test_ios.zsh` | Runs the native XCTest suite on the selected iPad or simulator. CI uses a simulator. |
| `build_macos.zsh` | Builds an unsigned Mac app in Debug or `Release`. Use it for compilation checks; an unsigned build is not a distributable DMG. |
| `run_macos.zsh` | Stops this checkout's existing Mac app, builds Debug, signs it with the local Developer ID identity and sandbox entitlements, then launches and checks the app process. Requires macOS 27 and a matching signing identity. |
| `check_macos_sandbox.zsh` | Checks the entitlement plist and **Release** Mac build settings for sandbox, outbound network, selected-file read access, bundle ID, and product name. It checks configuration, not runtime permissions. |
| `write_build_info.zsh` | Xcode build phase, run automatically, that writes build date and the compiling Mac's Computer Name into `BuildInfo.plist` for the window title. |
| `release_version.py` | Internal release helper that validates four single-digit version components, calculates carry after 9, and synchronizes `MARKETING_VERSION` and numeric build version in `project.yml` and both checked-in projects. `current` and `next` are available for inspection. |
| `release_notes.py` | Selects the last published release tag on the current history and writes release notes containing every commit subject and body since that tag, in chronological order. |
| `render_app_assets.zsh` | Renders the SVG app icon into the macOS sizes and opaque iPad/iPhone icon, and the static DMG Finder background. Requires `rsvg-convert` and ImageMagick. |
| `release_macos.zsh` | On a clean `main`, calculates the next version, regenerates the project, builds and Developer ID signs Release with hardened runtime, creates a DMG, submits it to Apple, staples and verifies it, then commits the version and generates notes from all commits since the previous published release. It opens the notes in Visual Studio Code with `code --wait` so you can edit them before the script pushes the matching tag and publishes the DMG. `--dry-run` reports the next and previous release versions without opening an editor. |

Examples:

```zsh
zsh Scripts/generate_project.zsh
SIMULATOR_UDID=YOUR_IPAD_SIMULATOR_UDID zsh Scripts/test_ios.zsh
zsh Scripts/build_macos.zsh Release
zsh Scripts/check_macos_sandbox.zsh
zsh Scripts/render_app_assets.zsh
zsh Scripts/release_macos.zsh --dry-run
zsh Scripts/release_macos.zsh
```

The release script requires Xcode, XcodeGen, the `code` command from Visual Studio Code, an authenticated GitHub CLI, a Developer ID Application certificate for the team in `project.yml`, and a usable `notarytool` Keychain profile. It uses this Mac's existing `MiMiNotary` profile by default and checks access before building; set `MIMITRENDS_NOTARY_PROFILE` only to use a different profile. Apple's [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) explains how profiles are stored; credentials stay in Keychain. `MIMITRENDS_MAC_SIGN_IDENTITY` can select a different installed identity for the same team. The version and GitHub Release title use exactly `0.0.0.0`: `0.0.1.9` advances to `0.0.2.0`. The script considers existing tags and releases, refuses to wrap after `9.9.9.9`, and stops before publication if signing, notarization, stapling, or verification fails. Release notes, DMGs, and notarization results stay under ignored `DerivedData/Releases/`. For the first release, notes include the full commit history; later releases include commits after the previous published release tag.

The Mac DMG contains the app and an Applications shortcut in a static Finder window. Its colored arrow is part of the background image; no installer helper runs.

## App Store preparation

The current app is a development skeleton and is **not ready for App Review**: position reconciliation, broader scanner behavior, and provider data rights remain incomplete; Scalable CSV transaction import is available in Settings. Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) require a complete, useful app, and the Mac App Store also requires sandboxing and Xcode-based packaging.

- The macOS Release target uses [App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox) with outgoing network access and read-only access to user-selected import files. It requests no unrestricted folder or incoming network access. The local Mac Debug build omits sandboxing so its diagnostic log can use `/tmp`; test Release separately for sandbox behavior. See [Storage and desktop data migration](Docs/DataStorage.md) for the planned container layout and migration rules.
- The iOS and macOS apps use SwiftUI and system APIs; the former JVM/JavaFX runtime is not bundled.
- The native app uses `org.senatov.mimitrends.apple` on both platforms so it can coexist with the existing macOS JVM app.
- The scripts produce local iPad, simulator, and Mac development builds. For App Store distribution, archive with Xcode, validate the archive, and submit through App Store Connect. Development and local ad hoc signing are not evidence of App Store approval. See Apple's [distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases).
- Before submission, complete the market features, review provider data rights and privacy disclosures, test on supported devices, and provide any account or demo access required for review.

## Next implementation stages

Progress and completion gates are tracked in [the porting plan](Docs/PortingPlan.md).

1. Define shared models for instruments, quotes, and signals, with tests against representative desktop outputs.
2. Port one provider adapter and its decoding, with secure credential storage where applicable.
3. Port scanner rules and SQLite persistence incrementally.
4. Complete position reconciliation and signal linking for imported Scalable trades.
5. Validate signed iOS and macOS archives, provider data rights, privacy disclosures, and sandbox behavior before App Store submission.

Scanning runs only while the app is active. No account-backed trade feed or subscription is started.

The chart header separates company identity, ticker, currency, price and data status. The Trades period shows the recent imported holding window with a short time margin instead of applying the rolling 1D cutoff. Other periods report imported trades outside their visible interval and offer Show trade history. Historical candle backfill includes available pre/post-market observations to cover broker execution times; the normal market scanner still requests regular-session candles.

Daily chart history for 1W and 1Y summarizes saved Yahoo minute candles. Days without saved bars remain empty.
