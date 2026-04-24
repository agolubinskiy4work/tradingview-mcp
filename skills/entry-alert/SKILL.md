---
name: entry-alert
description: Configure the user's TV Entry Finder / Playbook Entry Finder indicator and create entry alerts. Use when the user says commands like "entry alert short set", "entry alert long set", "entry alert both set", or asks to set an entry alert through the indicator.
---

# Entry Alert Workflow

This workflow configures the user's manual entry finder indicator and creates a TradingView alert for entry confirmation.

The user's saved Pine script is named `TV Entry Finder`, while the indicator title on chart is usually `Playbook Entry Finder`. The Pine version may change, so do not rely on a fixed version number.

## Supported Chat Commands

Treat these as command shortcuts:

- `entry alert short set` — set the indicator direction to `Short` and create an alert.
- `entry alert long set` — set the indicator direction to `Long` and create an alert.
- `entry alert both set` — set the indicator direction to `Both` and create an alert.
- `entry alert off` — do not delete alerts automatically unless the user explicitly asks; set `Finder active` to false if the indicator is found.

Also support natural language variants like:

- "поставь entry alert short"
- "создай alert на short через TV Entry Finder"
- "включи поиск входа в лонг"

## Indicator Identification

1. Call `chart_get_state`.
2. Find a study whose name includes one of:
   - `Playbook Entry Finder`
   - `TV Entry Finder`
   - `Entry Finder`
3. If multiple matching studies exist, prefer the visible one. If still ambiguous, ask the user which one to use.
4. If no matching study exists, tell the user to add `TV Entry Finder` to the chart first, or open it through Pine scripts.

## Input Mapping

For the current script version, expected inputs are:

- `in_0`: `Finder active` boolean.
- `in_1`: `Direction`, one of `Both`, `Long`, `Short`.
- `in_2`: `Structure fractal length`.
- `in_3`: `Alert only on closed candles`.
- `in_4`: `Show labels`.

Use `data_get_indicator` if needed to confirm the input IDs. Do not assume old entity IDs across sessions.

## Set Direction

For `entry alert short set`:

1. Make sure the indicator is visible with `indicator_toggle_visibility`.
2. Use `indicator_set_inputs` with:
   - `{"in_0": true, "in_1": "Short"}`

For `entry alert long set`:

1. Make sure the indicator is visible.
2. Use `indicator_set_inputs` with:
   - `{"in_0": true, "in_1": "Long"}`

For `entry alert both set`:

1. Make sure the indicator is visible.
2. Use `indicator_set_inputs` with:
   - `{"in_0": true, "in_1": "Both"}`

For `entry alert off`:

1. Use `indicator_set_inputs` with:
   - `{"in_0": false}`
2. Do not delete active alerts unless explicitly requested.

## Create The Alert

Preferred condition:

- Indicator: `Playbook Entry Finder` / `TV Entry Finder`.
- Alert condition: `Any playbook entry`.
- Resolution: current chart timeframe, usually `15m`.
- Message:
  - Short: `Entry Finder SHORT on {{ticker}} {{interval}}. Check playbook before entry.`
  - Long: `Entry Finder LONG on {{ticker}} {{interval}}. Check playbook before entry.`
  - Both: `Entry Finder signal on {{ticker}} {{interval}}. Check playbook before entry.`

Automation steps:

1. Open the alerts panel if needed with `ui_open_panel`.
2. Click `Create alert`.
3. Select the matching `Playbook Entry Finder` / `TV Entry Finder` source.
4. Select `Any playbook entry`.
5. Create the alert.
6. Verify with `alert_list`.

If the UI cannot reliably create or activate the alert, still complete the indicator configuration and give the user exact manual steps:

1. Click `Alert`.
2. Condition: `Playbook Entry Finder` or `TV Entry Finder`.
3. Trigger: `Any playbook entry`.
4. Create.

## Verification

After setting the alert, report:

- Symbol and timeframe.
- Indicator entity ID used.
- Direction set.
- Whether the alert appears in `alert_list`.
- Whether TradingView reports it active, if available.

If TradingView reports an alert as inactive while the UI shows it active, say that MCP may read alert status differently and that the user's UI state should be trusted.
