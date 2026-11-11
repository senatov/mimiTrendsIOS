# Desktop preferences and native Settings

The native app keeps its own settings and does not import the Kotlin desktop app’s configuration or credentials. Existing native preferences remain authoritative.

| Desktop source | Native handling |
| --- | --- |
| `scanner.properties` movement thresholds | **Settings → Rapid moves** edits drop, rebound, turnover, and volume thresholds used by the automatic Yahoo candle scan. |
| `scanner.properties` result count and age | **Settings → Scanner** filters saved Radar results without deleting their history. |
| `ui-state.properties` selected symbol and chart range | Saved in native preferences and restored on relaunch. |
| `scanner.properties` theme and table colours | **Appearance** and **Color Table** hold native controls. |
| `provider-urls.properties` | Supported ranking and quote URLs can be edited under **Market data providers**. |
| `finnhub.properties` | Ignored. The native app no longer uses a Finnhub API key or webhook secret. |
| JavaFX window geometry | Not imported; SwiftUI saves its own panel ratios. |

The watchlist, candle bars, signal history, and imported trades remain in native SQLite stores. Scanning runs only while the app is active.
