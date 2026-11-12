# Confirmed local reversals

Radar's **Confirmed reversal** signal uses completed Yahoo minute candles with reported volume. It looks for a decline into a local closing low, an intervening high, a pullback that holds a higher closing low, and a fresh close above the intervening high. This is the standard *higher low and higher high* price confirmation described by Charles Schwab. A simple rise from the lowest close is insufficient: a brief bounce during a continuing decline does not establish a reversal.

## Rule in the app

1. The first local low must follow a decline of at least the configured percentage within the preceding 15 minutes. It must be below the neighboring closes.
2. A later local low must be higher than the first and lower than its neighboring closes. Prices between the two lows must stay above the first low.
3. The newest completed close must cross above the highest close between those lows, with the preceding close at or below that level. The net rise from the first low must meet the configured percentage, and the low-to-breakout time must fit the configured window.
4. Existing freshness, reported-volume, gap, minimum-price and 30-minute turnover checks still apply. The stored signal retains the actual breakout time and the first low as its reference price.
5. Before displaying saved reversals, Radar checks the latest locally stored candle. If a later close reaches or falls below the first low, the old reversal is hidden. An absent newer candle is not treated as confirmation or as failure; the displayed event time remains visible.

The price pattern comes from the cited source. The 15-minute context, configurable percentage and window, close-based pivots, and volume thresholds are **app-specific screening choices**, not values prescribed by the source. They should be assessed against historical signals before being treated as calibrated trading thresholds. The scanner cannot identify the exact bottom in real time: waiting for a higher low and breakout creates a confirmation delay, and a confirmed pattern can still fail. The signal is an observation, not an order or a prediction of profit.

For the Micron Technology (`MU`) example on 12 November 2026, the old rule found a 0.81% rise from the 15:56 close to 15:59. There was no higher low and breakout in those bars; the new rule does not emit a reversal for that sequence. Old **Sharp rebound** and **Rapid rise** records remain in storage for audit but are omitted from the current Radar list.

## Sources

- Charles Schwab, [How to Read Stock Charts and Trading Patterns](https://www.schwab.com/learn/story/how-to-read-stock-charts-and-trading-patterns), “Reversals and breakout patterns”: a downtrend reversal needs a higher high and a higher low to distinguish it from a short rally.
- Charles Schwab, [Trading Volume as a Market Indicator](https://www.schwab.com/learn/story/trading-volume-as-market-indicator): volume can help confirm or question a price move. The app uses reported volume as a quality gate; its numeric threshold is app-specific.
