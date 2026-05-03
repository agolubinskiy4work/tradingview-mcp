---
name: qdrant-search
description: Search the user's Qdrant trading notes/transcripts. Use when the user says "#rag", "#qdrant", "#notes", "поищи в базе", "найди в заметках", "что говорилось про", asks to search transcripts, notes, database, or previous trading discussions.
---

# Qdrant Search Workflow

Use this skill to search the user's trading transcript and notes database through Qdrant MCP.

## Triggers

Use this workflow when the user says:

- `#rag <query>`
- `#qdrant <query>`
- `#notes <query>`
- `поищи в базе ...`
- `найди в заметках ...`
- `что говорилось про ...`
- `найди в транскриптах ...`
- asks about previous notes, streams, transcripts, Hadiukov backtests, swing/intraday rules, risk, RR, timeframes, invalidation, FVG, iFVG, BOS, stop placement, or entry timing.

## Required Tool

Always use:

- `qdrant_qdrant-find`

Do not answer from memory if the user explicitly asks to search the database.

## Search Rules

1. Extract the core search query from the user message.
2. Run `qdrant_qdrant-find` with that query.
3. If results are weak, too broad, or miss the user's intent, run one additional search with synonyms or a shorter query.
4. Prefer Russian query terms for Russian transcripts, but include English trading terms if relevant: `swing`, `intraday`, `timeframe`, `FVG`, `iFVG`, `BOS`, `RR`, `стоп`, `таргет`, `инвалидация`.
5. Do not invent notes that were not found.
6. If Qdrant fails, state the exact error briefly.

## Answer Format

Answer in Russian by default.

Use this structure:

```md
Нашел в базе:

- <main point 1>
- <main point 2>
- <main point 3>

Вывод: <practical conclusion>

Источник/фрагмент:
> <short relevant quote or paraphrase>
```

If the query is about trading rules, end with a practical rule:

```md
Практическое правило: <what to do>
```

## Important

- Qdrant is the source of truth for this workflow.
- If search results conflict, say that notes are mixed and explain both versions.
- If nothing relevant is found, say: `В базе не нашел достаточно релевантных заметок по этому запросу.`
