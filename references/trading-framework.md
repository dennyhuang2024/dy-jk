# DY JK Trading Framework

Use this checklist to avoid single-factor decisions.

## A. Common-Sense Layer
1. Structure:
- Market cap and rank
- Liquidity proxy (24h volume / market cap)
- FDV vs market cap for unlock pressure

2. Money:
- 7d and 30d returns to classify regime (up/down/neutral)
- Only trust breakouts with volume expansion

3. Chips:
- Holder concentration and linked-cluster share
- Separate CEX, DEX, and contract wallets before interpretation

## B. Advanced Layer
1. Three-factor model:
- Market structure (trend + key levels)
- Capital quality (liquidity + turnover)
- Holder concentration (linked clusters)

2. Event-driven gating:
- If non-CEX linked cluster > 70%, treat as event-driven asset
- Use smaller size and faster invalidation than diversified assets

3. Risk triggers:
- Cluster-to-CEX transfer spike
- Support break with rising sell volume
- Failed breakout within 1-2 daily candles

## C. Decision Labels
- Low risk: linked non-CEX cluster < 30%
- Medium risk: 30-50%
- High risk: 50-70%
- Very high risk: > 70%

## D. Output Requirements
Always include:
- Snapshot timestamp
- Data scope (top holder count)
- All assumptions and caveats
