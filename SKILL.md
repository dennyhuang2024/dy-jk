---
name: dy-jk
description: Analyze token trading direction with a full dashboard that includes spot volume, derivatives volume, funding rate, holder concentration, and unlock pressure. Use when users ask for systematic token analysis, not just concentration checks, and need actionable risk interpretation in one command.
---

# DY JK

## Overview
Use this skill for a one-command token dashboard in Chinese by default.
It combines trading common sense and advanced signals: structure, spot flow, derivatives flow, futures/spot volume ratio, funding, long/short positioning, concentration, and unlock overhang.

## One Command (recommended)
```bash
/Users/denny/.codex/skills/dy-jk/scripts/build_trade_report.sh \
  --address <TOKEN_ADDRESS> \
  --chain <solana|eth|...> \
  --date YYYY-MM-DD \
  --count 250 \
  --lang zh \
  --proxy http://127.0.0.1:7897
```

## Output Behavior
- Primary output: structured dashboard printed to stdout (for direct chat reply).
- Optional file output: pass `--out <path>` if needed.

## Metrics Included
1. Structure: price, mcap, FDV, rank, returns.
2. Spot: 24h spot volume, sampled venue breakdown, and exchange coverage.
3. Derivatives: Coinglass-first perp 24h quote volume, futures/spot volume ratio, funding rate, open interest, and long/short ratio.
4. Holder structure: top-holder coverage, non-CEX concentration, linked-cluster concentration.
5. Unlock pressure: circulating ratio, unlock overhang, FDV/MCAP.
6. Unlock event backtest: average pre7/post7/post14 returns around scheduled unlock dates (when preset exists).
7. Risk interpretation: regime + concentration risk + trigger rules.

## Notes
- Default language: Chinese.
- Depend on `curl`, `jq`, `node`, `awk`.
- Set `COINGLASS_API_KEY` (or `CG_API_KEY`) to enable Coinglass spot/futures metrics.
- If external APIs are blocked, use `--proxy`.
- Keep execution as a single command to avoid repeated approval interruptions.
- Unlock event backtest uses preset schedules in `/Users/denny/.codex/skills/dy-jk/references/unlock-presets.json`.
