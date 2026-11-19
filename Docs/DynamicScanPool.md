# Radar candidate pool

This document describes the current SwiftUI Radar. The Kotlin desktop app remains a reference for signal semantics, but its WallstreetONLINE ranking pool and provider subscriptions do not drive this pool.

## Candidate selection

1. While Radar is active, `TradingViewVolatilitySource` requests German and US activity and volatility screeners about every ten minutes. Activity is ranked by traded value, without a volatility threshold, so liquid large-cap shares can remain in the pool on quiet days. The volatility ranking continues to find fast movers. Both accept Xetra, NASDAQ, NYSE, and NYSE American shares that pass the app's price, market-capitalization, traded-value, and Yahoo-symbol checks. Successful candidates include a ticker, company name, and ISIN. The configured volatility pages are fallback inputs for the volatility ranking; a page row without an ISIN cannot pass the EIX check.
2. `EIXInstrumentSource` downloads the opening public [EIX pre-trade file](https://european-investor-exchange.com/de/pretrade) for the newest available trading day and collects its ISINs. This set refreshes hourly. The last successful set is kept locally for up to 48 hours; a failed refresh retries after five minutes. The source must contain at least 5,000 distinct ISINs before replacing the saved set.
3. `MarketRadarScanner` keeps only TradingView candidates whose ISIN occurs in that EIX set. `RadarScanPool` reserves priority for up to 96 active US shares and 64 active German shares, interleaved while their markets are open. It fills remaining slots from the volatility rankings, removes duplicates, and caps the result at 255. Filtering precedes the cap, so a rejected share does not occupy a pool slot. The pool can contain fewer than 255 shares when sources or markets provide fewer eligible candidates.
4. The scanner evaluates completed Yahoo minute candles with reported volume. TradingView ranks candidates and EIX constrains the universe; neither supplies the candle signal or an executable broker quote. The watchlist selects a chart symbol and does not override the automatic pool.

The Sources panel labels the resulting list **EIX candidates**. It reports how many symbols have been checked, how many candle histories were usable, and source errors. Stored signals remain in the signal database, but the visible Radar list includes only symbols in the current TradingView candidate set with an ISIN observed in the EIX file. A fresh EIX or TradingView failure may temporarily reduce the visible list; lack of a valid EIX set leaves it empty. Activity and volatility snapshots are cached separately, so one ranking can remain available if the other fails.

## Meaning of the EIX check

The public pre-trade files are exchange observations, not a complete Scalable broker catalogue or a live order-eligibility API. Their ISIN membership is a conservative inclusion rule. Absence from the selected file does not prove that a share is unlisted at EIX, unavailable through another Scalable venue, or unavailable at another broker. Presence does not guarantee that a buy order can be placed now; trading halts, account rules, and broker restrictions can still apply. The app does not sign in to Scalable or place orders.

The filter uses the newest day's opening file, not every update of the delayed pre-trade feed. That keeps network and parsing work bounded on iPad. Provider outages use the cached EIX set within its 48-hour window and do not turn unverified symbols into eligible candidates.

## Other market inputs

Lang & Schwarz quotes are stored separately from Yahoo's completed, volume-backed candles and do not confirm candle signals. A signal from any stored source is subject to the visible-list EIX check. See [README.md](../README.md) for the current scan thresholds and [DataStorage.md](DataStorage.md) for cache locations.

## Data and distribution

TradingView page parsing and undocumented screener access require a data-rights review before distribution. EIX pre-trade files are publicly downloadable, but their publication does not by itself establish redistribution or broker-data rights for a commercial app. Keep the source adapters separate so a licensed instrument catalogue can replace the conservative EIX observation set later.
