---
name: analyze-situation
description: Analyze the current selected TradingView asset through the user's playbook and explain what is happening now. Use when the user says "analyze situation", "проанализируй ситуацию", asks what is happening now, or asks whether to wait for entry, test, confirmation, or invalidation.
---

# Analyze Situation Workflow

This workflow gives a practical situation read on the currently selected TradingView asset using the user's trading playbook.

Use this when the user says:

- `analyze situation`
- `analyze current situation`
- `проанализируй ситуацию`
- `что сейчас происходит?`
- `есть ли вход или ждем?`
- `был тест или нет?`

## Required Strategy Context

Use the rules in:

`strategies/my-trading-playbook.md`

The playbook is the source of truth. The answer must be practical, not generic technical analysis.

## Goal

Tell the user what is happening right now and what action fits the playbook:

- No plan.
- Waiting for zone test.
- Test is happening now.
- Test happened, waiting for 15m confirmation.
- Entry formed.
- Entry missed or too late.
- Plan invalidated.
- Range trade context.
- Do nothing because price is in the middle or conditions are dirty.

## Data Gathering

Start compact and expand only if needed:

1. `chart_get_state` — current symbol, timeframe, studies, entity IDs.
2. `quote_get` — current price.
3. `data_get_ohlcv` with `summary: true` on the current timeframe.
4. `data_get_pine_boxes` with `study_filter: "FVG"` — read visible FVG/iFVG zones.
5. `data_get_study_values` — current visible indicator values.

If the current timeframe is 15m or lower, also check 4H context:

1. Temporarily switch to `240` with `chart_set_timeframe`.
2. Read `data_get_ohlcv` with `summary: true`.
3. Read `data_get_pine_boxes` with `study_filter: "FVG"`.
4. Switch back to the original timeframe.
5. Read recent 15m bars with `data_get_ohlcv` using `count: 40`, `summary: false` if confirmation needs to be judged.

If the current timeframe is 4H or higher, use current chart as context and only switch to 15m if the user asks for entry confirmation or if the situation clearly requires it.

## Analysis Checklist

Answer these internally before responding:

1. What asset and timeframe are selected?
2. Is this primarily EURUSD or another asset? If another asset, note that the playbook is tuned mainly for EURUSD but can be applied mechanically.
3. Is price trending, ranging, testing a 4H zone, or in the middle?
4. Is there a clear 4H zone, FVG/iFVG, range boundary, or FTA nearby?
5. Has the zone/boundary been tested?
6. Is the test happening right now or already finished?
7. Is there 15m confirmation: BOS, iFVG, or new FVG in the planned direction?
8. Is the setup invalidated by 4H close, FVG inversion, strong opposing FTA, or failed range behavior?
9. Is the entry too late or already missed?
10. What exactly should the user wait for next?

## Setup Status

Every answer must include exactly one status:

- `No Plan`
- `Waiting For Zone Test`
- `Testing Zone Now`
- `Waiting For 15m Confirmation`
- `Valid Setup`
- `Invalidated`
- `Missed / Too Late`

Use `Testing Zone Now` when price is currently inside or directly sweeping the planned 4H zone/range boundary, but confirmation is not ready yet.

## Recommendations

Recommendations must be action-oriented:

- `Do nothing` when the playbook has no setup.
- `Wait for test` when zone is not reached.
- `Wait for 15m confirmation` after test.
- `Watch for return into range` after boundary sweep.
- `Alert can be set` when only mechanical entry confirmation remains.
- `No entry` when confirmation is absent.
- `Plan invalidated` when the situation is cancelled.

Do not recommend entering only because price touches a zone. Touching a zone is not an entry.

## Output Format

Use this concise format:

```md
Situation: <one sentence>
Setup Status: <required status>

Context: <HTF / 4H / range context>
Zone/Test: <zone, boundary, whether test is happening or done>
15m Entry Trigger: <BOS / iFVG / new FVG / missing>
Invalidation: <what cancels the plan>
Recommendation: <wait / no trade / set alert / valid entry / stop tracking>
Next Condition: <the exact next thing to wait for>
```

If the setup is incomplete, say `входа нет` clearly.

## Tone

- Direct and practical.
- Russian is preferred if the user writes in Russian.
- Avoid generic market education.
- Make a clear distinction between test, confirmation, and entry.
