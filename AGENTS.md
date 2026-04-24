# TradingView MCP OpenCode Instructions

This project is configured for OpenCode. The canonical workflow rules remain in `CLAUDE.md`, and `opencode.json` loads that file through the `instructions` setting.

## OpenCode Discovery

- Project skills live in `.opencode/skills/<name>/SKILL.md` so the OpenCode `skill` tool can discover them.
- Project agents live in `.opencode/agents/*.md` and can be invoked with `@agent-name`.
- The local MCP server is configured in `opencode.json` as `tradingview`, started with `npm run start`.

## Repository Conventions

- Keep Claude-compatible source files in `skills/` and `agents/` unless intentionally migrating them.
- When changing a skill or agent, update the matching `.opencode/` copy as well.
- For TradingView workflows, follow the decision tree in `CLAUDE.md` and the relevant skill instructions.
- Default response language is Russian unless the user explicitly requests another language; this applies to normal requests, skills, agents, reports, and summaries.
