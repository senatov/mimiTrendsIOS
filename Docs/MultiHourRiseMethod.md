# Multi-hour rise in Radar

Radar checks the TradingView most-volatile stock universe for both the US and
Germany. After the first hour of regular trading, a separate rising-stock query
refreshes every 10 minutes. It reserves up to 24 places in the 255-symbol Yahoo
minute-bar scan pool. An EIX-observed ISIN is still required. The rising-stock
query uses the same TradingView screener data as the most-volatile pages; it
does not treat a daily percentage gain as a Radar signal.

To admit smaller but actively traded shares such as CUE, this lane accepts a
price of at least 2 and a market capitalization of at least 25 million. US
shares need at least 10 million in daily traded value and a daily gain of 10%.
Xetra shares need at least 250,000 in traded value and a daily gain of 5%.
Other Radar discovery lanes keep their existing thresholds.

The `Multi-hour rise` signal is calculated from completed Yahoo minute bars in
the current regular session, including a short period immediately after the
close. Its anchor is the lowest eligible close at least 90 minutes before the
latest close. The window is at most six hours. A US signal requires a gain of
15%, at least 10 million in reported turnover during the move, and at least
1 million in the last hour. Xetra thresholds are 8%, 250,000, and 50,000.
Both markets require at least 60 reported bars, no gap over five minutes, a
maximum close-to-close pullback of 12%, an ending close within 10% of the
move's highest close, and gains in at least half of 20-minute samples.

Radar displays the complete move duration and gain, with an event badge that
identifies the multi-hour signal. A newer price removes the signal if it gives
back more than half the gain from the anchor. The badge describes a movement,
not a recommendation to buy; the event detail asks the user to check current
liquidity for these high-volatility shares.

TradingView supplies discovery candidates, Yahoo supplies the movement and
reported volume, and EIX checks whether the instrument has been observed.
Provider outages, delayed German bars, sparse trading, and the finite scan
pool can still delay or prevent a signal.
