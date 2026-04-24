# My Trading Playbook

This playbook describes the user's discretionary intraday trading model. The primary market is EURUSD. Use this as the source of truth before giving trade advice, market direction, setup validation, or TradingView MCP analysis.

## Strategy Identity

- Main style: intraday execution based on higher-timeframe context.
- Primary market: EURUSD.
- The model is not a standalone 15m pattern system. Intraday trades must come from a higher-timeframe plan.
- The advisor must not invent setups from isolated 15m patterns.
- If the higher-timeframe plan is unclear, the correct answer is no trade.

## Timeframe Hierarchy

- Weekly / Daily: define broad context, liquidity, major targets, and caution zones.
- 4H: define the working zone, range boundaries, FVG/iFVG context, FTA, and trade location.
- 15m: execution and confirmation only.

Core rule: do not open 15m to search for ideas. Open 15m only after the plan already defines:

- Where price should trade from.
- Where price should trade to.
- The active 4H zone or range boundary.
- The logical target.
- The invalidation condition.

## 4H Zone Logic

- Intraday setups usually start from a 4H zone.
- Price must test the 4H zone before an entry can be considered.
- A 4H zone without a test is only a waiting condition.
- After the test, move to 15m and look for a clean reaction.
- The 4H zone provides location; 15m provides entry confirmation.

## 15m Entry Confirmation

Valid 15m confirmation means the zone produced an observable reaction. The model accepts three main confirmation types:

- Structure break: price breaks a local fractal and closes with the candle body.
- 15m FVG inversion: price cleanly closes through the opposite imbalance.
- New 15m FVG in trade direction: a fresh imbalance forms as evidence of reaction.

Important rules:

- No test of the zone means no entry.
- No clean confirmation means no entry.
- A near close, almost break, or weak partial interaction is not enough.
- The exact label of the pattern is less important than the fact that price clearly reacted from the planned zone.
- Do not enter just because an imbalance exists. FVG without context is not a trade.

## Range / RNG Rules

Signs of a range:

- No normal volatility.
- No strong imbalances.
- Price rotates between structural points.
- The whole area can be marked as a rectangle.

How to trade a range:

- Mark the upper boundary.
- Mark the lower boundary.
- Avoid trades in the middle without a clear reason.
- Prefer interaction with range boundaries.
- Range boundaries can be traded more aggressively than trend contexts, but confirmation is still preferred.
- A strong spike outside the range does not automatically cancel the range if price continues respecting the boundaries.
- If boundary reactions become consistently weak, stop trading the range because it is becoming broken and choppy.

Range boundary adjustment:

- Move range boundaries only after price tests the boundary and returns back into the range.
- Then set the boundary at the new high or low.

Range inversion:

- If price sweeps a range boundary and then forms an FVG or iFVG, this can count as a reversal condition.

Range aggression:

- In a 4H range, aggressive trading is allowed.
- After price sweeps a boundary and the next candle returns into the range, move to 15m and look for an entry.
- Stop should be behind the swept boundary.

Large stop in range:

- If the stop behind the range boundary is too large, prefer a limit order to improve RR.

## FVG / iFVG Rules

- FVG and iFVG are contextual tools, not standalone entry reasons.
- A 4H FVG can be the working zone.
- A 15m iFVG can be an entry confirmation after a 4H zone test.
- A new 15m FVG in the trade direction can confirm reaction from the zone.

4H FVG inversion invalidation:

- If price tests a 4H FVG and the latest 4H candle closes beyond the FVG against the planned reaction, the plan is invalid.
- After this invalidation, do not take more positions from that situation.

15m invalidation during 4H FVG test:

- If price tests a 4H FVG and, on 15m, a candle overlaps or invalidates the previous FVG in the same direction as the plan in a way that cancels the intended reaction, the plan is invalid.
- After this invalidation, do not take more positions from that situation.

## No-Trade Conditions

Do not enter when:

- There is no clear Weekly / Daily / 4H plan.
- The 4H zone has not been tested.
- There is no clean 15m confirmation after the zone test.
- A strong opposing zone, Daily zone, or 4H FTA blocks the trade.
- A strong weekly target or weekly fractal has just been taken and the context is overextended.
- The market is dirty, slow, choppy, or low-volatility without clean reactions.
- Price is in the middle of a range without a specific reason.
- The entry is too late in the session.
- The setup relies only on seeing an imbalance without context.

Timing filters:

- 19:00 can still be acceptable depending on context.
- 22:00 is usually too late.
- 23:00 is too late.
- Deep-night entries may be valid in backtest statistics but are often not realistic live trades.
- If the realistic action is to wait for Frankfurt / London, say so.

## Sessions And Timing

- 09:00, Frankfurt / London open, is important.
- One specific setup subtype: the zone was tested at night or during Asia, reaction started, and at 09:00 a market entry is taken with the stop behind Asia or the manipulation.
- This 09:00-after-night-test entry is not automatically ideal.
- It must be tracked separately in the journal.

Journal tags to use when relevant:

- 09:00 entry.
- Stop behind Asia.
- Entry after 19:00.
- Re-entry.
- Resweep.
- Night test.
- Range boundary trade.
- FVG inversion.

## Direction And Context

- Priority is trading with the higher-timeframe direction.
- Countertrend intraday trades are allowed only as local, conscious exceptions inside a clear plan.
- Do not treat a local countertrend intraday move as a full swing reversal.
- Avoid or downgrade trades against strong higher-timeframe imbalance, Daily zones, or strong 4H FTA.

## Stops, Targets, And RR

- Think in R / RR, not account percentages.
- Risk should be consistent.
- Increasing risk does not improve the system; it only accelerates outcomes.
- Default target is usually fixed 2R.
- Taking 2R is preferred for stable win rate and better psychology, even when theoretical potential is larger.
- It is acceptable to take less than 2R, such as 1.5R, 1.6R, or 1.8R, when an obvious target is closer.
- Do not force 2R if the logical target is nearer.
- Do not adjust the stop just to create attractive RR.
- The stop should be placed at the technically correct location.
- Improve RR through entry quality or target selection, not by forcing the stop.
- Common stop locations: behind local high/low, behind Asia, behind manipulation, or behind a swept range boundary.

Execution:

- Market entries are acceptable in intraday.
- Limit orders are acceptable when volatility is high or a better RR is needed.
- In range trades with a large stop, prefer a limit entry.

## Re-Entry And Resweep Rules

- After a stop, only one re-entry is allowed for the same idea.
- A re-entry is allowed only if the context remains valid.
- The target must still be relevant.
- The zone must still be relevant.
- A new structure break, inversion, or FVG confirmation must appear.
- If the second entry also stops out, do not trade that idea again.
- Resweep is a normal intraday event: first entry stops, price resweeps, then a new inversion or break gives the second valid entry.

## News And Volatility

- News does not automatically cancel a trade.
- Evaluate news strength and distance to stop.
- If the stop has enough structural distance, the news may be acceptable.
- After news, a new entry can still be valid if clean 15m confirmation forms.
- Bad volatility is a poor intraday environment. Dirty, slow, choppy price action reduces setup quality.

## Common Risks And Mistakes

- Missing valid systematic trades must be tracked in the journal.
- Missed trades distort monthly evaluation.
- Loss of focus, working away from the usual trading environment, travel, and distraction are real performance risks.
- Trying to stretch every trade to 4R or 5R can reduce win rate and worsen psychology.
- Do not overtrade choppy or weak-volatility markets.

## Advisor Setup Status

Every analysis must classify the current situation as one of these statuses:

- No Plan: higher-timeframe context is unclear.
- Waiting For Zone Test: plan exists, but the 4H zone has not been tested.
- Waiting For 15m Confirmation: zone was tested, but entry confirmation is missing.
- Valid Setup: plan, zone test, target, invalidation, and confirmation are present.
- Invalidated: the plan was cancelled by FVG inversion, opposing zone, failed range reaction, or another invalidation rule.
- Missed / Too Late: setup may have occurred, but the entry is no longer valid or the session timing is poor.

## Advisor Output Format

When analyzing a chart, answer in this structure:

- Symbol and timeframe context.
- Bias: bullish, bearish, or neutral.
- Setup status: one of the required statuses.
- HTF context: Weekly / Daily / 4H summary if available.
- 4H zone or range boundary: active zone, tested or not tested.
- Target: nearest logical target and whether 2R is realistic.
- 15m confirmation: structure break, iFVG, new FVG, or missing.
- FTA / opposing zones: what blocks or reduces quality.
- Entry idea: market, limit, or wait.
- Stop location: technical stop location, not forced for RR.
- Take profit: usually 2R, or closer logical target if needed.
- Invalidation: what cancels the plan.
- Timing/session notes: late entry, 09:00 setup, Asia stop, news, etc.
- Journal tags: applicable tags.
- What must happen next: precise condition to wait for.

If the setup is incomplete, do not provide a forced entry. Say exactly what is missing.
