# Kotlin-to-Swift porting status

The Kotlin/JavaFX MiMiTrends project is an archived behavioral reference. The active product is the SwiftUI `mimiTrends-iOS` app for iPadOS 27, with a Mac target. This page records the current state and remaining porting work; it is not an implementation plan for the removed Finnhub integration.

| Area | Current native state | Remaining work |
| --- | --- | --- |
| Market models | Native instruments, quotes, minute bars, and signal results have tests and local stores. | Recheck desktop parity when adding a new detector or provider. |
| Candidate discovery | TradingView volatility candidates are matched by ISIN to the public EIX pre-trade file before the 255-symbol Radar pool is filled. The EIX set is cached for up to 48 hours. | Obtain a complete, licensed venue or broker catalogue if exact tradability is required. |
| Candle scanning | Yahoo completed minute candles with reported volume drive rapid drops, confirmed reversals, and longer moves while the app is active. | Evaluate provider coverage, rate limits, data rights, and detection quality on real devices. |
| Radar and charts | Radar shows EIX-observed candidates and filters saved signals to the current verified candidate set. The selected chart uses locally stored or fetched Yahoo candles, volume, and EMA lines. | Finish device and accessibility checks across iPad and Mac layouts. |
| Portfolio | A device-local watchlist and Scalable transaction CSV importer exist. The app has no live Scalable account connection. | Reconcile imported positions and link trades to signals if needed. |
| Distribution | A Mac DMG release path exists; the iPad App Store release is pending. | Complete data-rights, sandbox, archive, and review checks. |

## Current Radar data path

`TradingViewVolatilitySource` selects candidate shares and supplies their ISINs. `EIXInstrumentSource` reads the newest day's opening public pre-trade file. `MarketRadarScanner` intersects the two by ISIN, applies the market-session gate, and fills up to 255 slots from the remaining candidates. A rejected candidate is replaced by the next eligible one. The public EIX file is an observation set, not proof of Scalable buy eligibility. See [DynamicScanPool.md](DynamicScanPool.md) for refresh, caching, and failure behavior.

`YahooRadarSource` supplies completed minute bars and reported volume for the accepted symbols. Detectors save results in the native signal database. Radar reads bounded history and displays only symbols that still belong to the current EIX-verified TradingView candidate set. A selected symbol or watchlist entry can still open its chart; it does not expand the automatic scan pool. The [confirmed reversal method](ConfirmedReversalMethod.md) documents that detector's price pattern.

## Storage and platform boundary

The native app owns its SQLite stores and preferences inside each device's app container. It does not open the live Kotlin database or synchronize the watchlist between devices. The Scalable CSV importer reads a user-selected file and does not authenticate to the broker. [DataStorage.md](DataStorage.md) details these boundaries.

Native code should keep network and database work off the main actor and stop active scanning when the scene leaves the foreground. iPadOS 27 is the primary interaction target; shared UI changes must also be checked on the Mac target. Data rights and actual broker availability remain separate from a successful build or a visible EIX ISIN.
