# Storage and desktop data migration

The Kotlin desktop app currently stores its SQLite database and Java properties files under `~/.mimi/trends/`. The native Apple app uses a different bundle identifier and each installation has its own sandbox container. It must never assume that the desktop path is writable or available, especially on iPhone.

## What can be reused

| Desktop data | Native Apple approach |
| --- | --- |
| `mimitrends.db` | Export selected tables through bounded snapshots. Minute bars use a standalone SQLite snapshot of at most 360 bars for one symbol. The watchlist uses a JSON snapshot of at most 500 symbols and insertion times. The native app validates each file before merging it into its own Application Support databases. Broader migration requires additional schema mapping. Do not open the desktop app's live database in the native app. |
| `scanner.properties`, `provider-urls.properties`, `weekly-universe.properties` | Import supported keys selectively, validate values, and save native preferences. The `.properties` files are migration inputs, not the native app's permanent configuration format. |
| `ui-state.properties`, `window-state.properties` | Translate only portable preferences such as a selected symbol or chart range. JavaFX window coordinates and table columns do not map directly to iPhone layouts. Radar saves its own wide and stacked divider ratios in native device preferences; it does not reuse desktop pixel positions. |
| `finnhub.properties` and `.env` | Never copy credentials into ordinary app configuration. Ask the user to enter keys again or import them deliberately into Keychain. Do not log, bundle, or commit them. |
| `exchange-rate.properties` and downloaded market history | Treat data that can be fetched again as cache. Do not mix it with user-created portfolio or watchlist data in a purgeable location. |

The desktop database currently uses WAL mode and contains both reconstructible market data and durable user data such as broker trades. A live `mimitrends.db` file alone may omit recent transactions still in its WAL file. The bar exporter opens the source read-only, reads one bounded symbol in a consistent transaction, and creates a standalone rollback-journal snapshot. The native importer rejects WAL files and checks format, integrity, bar values, and currency metadata before a transactional import. Broader migration should start from a consistent SQLite backup or `VACUUM INTO` snapshot made by the desktop app, check its integrity and `schema_migrations`, then import it into a new native-owned database. The existing desktop schema was previously at migration 21; that number must be checked again when broader migration code is implemented.

The native app creates `mimitrends-native.db` for completed Finnhub and imported desktop minute bars, `mimitrends-signals.db` for detected signal history, and `mimitrends-watchlist.db` for user-selected symbols in Application Support. Each database has its own transactional native migration 1, WAL mode, integrity check, and `native_schema_migrations` table. Signal history stores the first accepted result for each symbol, source, and event time so repeated detector evaluations do not create duplicate events. The watchlist keeps the desktop table's symbol and `added_at` fields, but is a native-owned database. These are new native databases, not direct copies of desktop schema 21. The watchlist snapshot contains only symbols and insertion times, has a 128 KB file limit, and merges missing symbols transactionally. Broker trades, settings, and other desktop tables have not been ported.

Direct Lang & Schwarz and wallstreetONLINE page observations use `mimitrends-quotes.db`, separate from completed trade bars. Its `quote_observations` table stores normalized EUR price and optional EUR bid/ask, original source currency and price, conversion rate and timestamp, provider, instrument identity, and quote time. USD observations without a fresh EUR/USD conversion are rejected before display and storage. Duplicate provider/instrument/time observations are ignored and records older than 72 hours are pruned on each write. These quote observations do not satisfy the trade-volume requirements of the confirmed signal detectors. Existing Finnhub and Yahoo minute-bar paths still retain their source currency and require a separate conversion migration before they can meet an EUR-only product requirement.

## Native storage locations

- **Application Support:** user-created watchlists, imported trades, durable settings, and their database. Resolve the directory with Foundation's `FileManager` API inside the app container. These records should survive normal cache cleanup and backup.
- **Caches:** downloaded quotes, logos, and market history that the app can obtain again. The system may remove these files. If a future database still mixes durable and cache data, do not put the entire database in Caches or exclude the entire file from backup; split the data first.
- **UserDefaults:** small nonsecret preferences that fit native settings. Keep a versioned mapping from supported Java properties keys for one-time import.
- **Keychain:** API keys and other credentials.

Each iPhone, iPad, and Mac installation has its own container. A common source schema does not synchronize the database between devices. Decide on iCloud or a service only if cross-device synchronization becomes a product requirement.

## Sandbox access

The macOS target enables App Sandbox, outgoing network connections for market providers, and read-only access to files the user explicitly selects for import. It does not request incoming connections, unrestricted home-folder access, or write access to selected files. Use `fileImporter` for desktop database, settings, or broker CSV import; copy selected data into the container and release any security-scoped access after the import. iOS document selection also yields security-scoped URLs. Additional entitlements should be added only when a feature needs them.

The iOS Simulator build and test scripts use local ad hoc signing so Keychain works during development. The macOS build script produces an unsigned binary; `run_macos.zsh` signs its local Debug build with a stable Developer ID Application identity and the declared sandbox entitlements. This keeps the app's signing identity stable across rebuilds, avoiding repeated authorization for Keychain items. Previously stored items may request one authorization after the signing change. These development checks do not test App Store distribution signing or prove that every future file and network operation works. Before distribution, run the completed workflows in a distribution-signed sandboxed build and validate the archive in Xcode.
