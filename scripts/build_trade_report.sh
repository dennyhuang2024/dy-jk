#!/usr/bin/env bash
set -euo pipefail

ADDRESS=""
CHAIN="solana"
DATE_UTC="$(date -u +%F)"
COUNT="250"
OUT=""
RUN_CONCENTRATION="true"
LANGUAGE="zh"
PROXY="${DY_JK_PROXY:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --address) ADDRESS="$2"; shift 2 ;;
    --chain) CHAIN="$2"; shift 2 ;;
    --date) DATE_UTC="$2"; shift 2 ;;
    --count) COUNT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --skip-concentration) RUN_CONCENTRATION="false"; shift 1 ;;
    --lang) LANGUAGE="$2"; shift 2 ;;
    --proxy) PROXY="$2"; shift 2 ;;
    -h|--help)
      cat <<USAGE
Usage: build_trade_report.sh --address <TOKEN_ADDRESS> [--chain solana] [--date YYYY-MM-DD] [--count 250] [--skip-concentration] [--lang zh|en] [--proxy http://127.0.0.1:7897] [--out /tmp/report.md]
USAGE
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$ADDRESS" ]]; then
  echo "--address is required" >&2
  exit 1
fi

for cmd in curl jq node awk; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing dependency: $cmd" >&2; exit 1; }
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURL_OPTS=()
if [[ -n "$PROXY" ]]; then
  CURL_OPTS+=(--proxy "$PROXY")
fi

if [[ "$RUN_CONCENTRATION" == "true" ]]; then
  VERIFY_ARGS=(--address "$ADDRESS" --chain "$CHAIN" --date "$DATE_UTC" --count "$COUNT")
  if [[ -n "$PROXY" ]]; then
    VERIFY_ARGS+=(--proxy "$PROXY")
  fi
  "$SCRIPT_DIR/verify_concentration.sh" "${VERIFY_ARGS[@]}" >/tmp/dy_jk_verify_stdout.json
fi

if [[ ! -f /tmp/dy_jk_report.json ]]; then
  echo "Missing /tmp/dy_jk_report.json. Run verify_concentration.sh first or remove --skip-concentration." >&2
  exit 1
fi

case "$CHAIN" in
  solana) PLATFORM_ID="solana" ;;
  eth|ethereum) PLATFORM_ID="ethereum" ;;
  bsc) PLATFORM_ID="binance-smart-chain" ;;
  base) PLATFORM_ID="base" ;;
  arbitrum) PLATFORM_ID="arbitrum-one" ;;
  polygon) PLATFORM_ID="polygon-pos" ;;
  avax|avalanche) PLATFORM_ID="avalanche" ;;
  *) PLATFORM_ID="$CHAIN" ;;
esac

COIN_JSON="/tmp/dy_jk_coin.json"
TICKERS_JSON="/tmp/dy_jk_tickers_p1.json"
BITGET_JSON="/tmp/dy_jk_bitget_ticker.json"
UNLOCK_PRESETS_JSON="$SCRIPT_DIR/../references/unlock-presets.json"
MARKET_SOURCE_STATUS="ok"
DERIV_SOURCE_STATUS="partial"
UNLOCK_EVENT_STATUS="not_configured"
unlock_avg_pre7="N/A"
unlock_avg_post7="N/A"
unlock_avg_post14="N/A"
unlock_neg_pre7="N/A"
unlock_neg_post7="N/A"
unlock_neg_post14="N/A"
unlock_samples="0"
unlock_last_date="N/A"
unlock_last_pre7="N/A"
unlock_last_post7="N/A"

if ! curl -fsS "${CURL_OPTS[@]}" "https://api.coingecko.com/api/v3/coins/${PLATFORM_ID}/contract/${ADDRESS}" > "$COIN_JSON"; then
  MARKET_SOURCE_STATUS="unavailable"
  cat > "$COIN_JSON" <<'JSON'
{"id":"unknown","name":"unknown","symbol":"unknown","market_cap_rank":null,"market_data":{"current_price":{"usd":0},"market_cap":{"usd":0},"fully_diluted_valuation":{"usd":0},"total_volume":{"usd":0},"ath":{"usd":0},"ath_date":{"usd":"-"},"atl":{"usd":0},"atl_date":{"usd":"-"},"price_change_percentage_7d":0,"price_change_percentage_30d":0,"price_change_percentage_1y":0,"circulating_supply":0,"total_supply":0,"max_supply":0}}
JSON
fi

coin_id=$(jq -r '.id // "unknown"' "$COIN_JSON")
coin_name=$(jq -r '.name // "unknown"' "$COIN_JSON")
symbol=$(jq -r '.symbol // "unknown" | ascii_upcase' "$COIN_JSON")
rank=$(jq -r '.market_cap_rank // "null"' "$COIN_JSON")
price=$(jq -r '.market_data.current_price.usd // 0' "$COIN_JSON")
market_cap=$(jq -r '.market_data.market_cap.usd // 0' "$COIN_JSON")
fdv=$(jq -r '.market_data.fully_diluted_valuation.usd // 0' "$COIN_JSON")
vol24=$(jq -r '.market_data.total_volume.usd // 0' "$COIN_JSON")
ath=$(jq -r '.market_data.ath.usd // 0' "$COIN_JSON")
ath_date=$(jq -r '.market_data.ath_date.usd // "-"' "$COIN_JSON")
atl=$(jq -r '.market_data.atl.usd // 0' "$COIN_JSON")
atl_date=$(jq -r '.market_data.atl_date.usd // "-"' "$COIN_JSON")
chg7=$(jq -r '.market_data.price_change_percentage_7d // 0' "$COIN_JSON")
chg30=$(jq -r '.market_data.price_change_percentage_30d // 0' "$COIN_JSON")
chg1y=$(jq -r '.market_data.price_change_percentage_1y // 0' "$COIN_JSON")
circulating=$(jq -r '.market_data.circulating_supply // 0' "$COIN_JSON")
total_supply=$(jq -r '.market_data.total_supply // 0' "$COIN_JSON")
max_supply=$(jq -r '.market_data.max_supply // 0' "$COIN_JSON")

if [[ "$coin_id" != "unknown" ]]; then
  if ! curl -fsS "${CURL_OPTS[@]}" "https://api.coingecko.com/api/v3/coins/${coin_id}/tickers?include_exchange_logo=false&page=1" > "$TICKERS_JSON"; then
    MARKET_SOURCE_STATUS="partial"
    echo '{"tickers":[]}' > "$TICKERS_JSON"
  fi
else
  echo '{"tickers":[]}' > "$TICKERS_JSON"
fi

spot_ticker_count=$(jq -r '.tickers | length' "$TICKERS_JSON")
spot_volume_sample=$(jq -r '([.tickers[]?.converted_volume.usd // 0] | add) // 0' "$TICKERS_JSON")
spot_top_venues=$(jq -r '[.tickers[]? | {m:(.market.identifier // "unknown"),v:(.converted_volume.usd // 0)}] | group_by(.m) | map({market:.[0].m, vol:(map(.v)|add)}) | sort_by(.vol) | reverse | .[0:5]' "$TICKERS_JSON")

symbol_pair="${symbol}USDT"
if curl -fsS "${CURL_OPTS[@]}" "https://api.bitget.com/api/v2/mix/market/tickers?productType=USDT-FUTURES" > "$BITGET_JSON"; then
  deriv_line=$(jq -r --arg s "$symbol_pair" '.data[]? | select(.symbol==$s) | [.symbol,.quoteVolume,.fundingRate,.holdingAmount,.markPrice,.indexPrice] | @tsv' "$BITGET_JSON" | head -n1)
  if [[ -n "$deriv_line" ]]; then
    DERIV_SOURCE_STATUS="ok"
    IFS=$'\t' read -r deriv_symbol deriv_quote_vol deriv_funding deriv_oi deriv_mark deriv_index <<< "$deriv_line"
  else
    DERIV_SOURCE_STATUS="not_listed"
    deriv_symbol="N/A"; deriv_quote_vol="0"; deriv_funding="N/A"; deriv_oi="N/A"; deriv_mark="N/A"; deriv_index="N/A"
  fi
else
  DERIV_SOURCE_STATUS="unavailable"
  deriv_symbol="N/A"; deriv_quote_vol="0"; deriv_funding="N/A"; deriv_oi="N/A"; deriv_mark="N/A"; deriv_index="N/A"
fi

CONC_JSON="/tmp/dy_jk_report.json"
top_cov=$(jq -r '.top_holders_coverage_pct // 0' "$CONC_JSON")
non_cex=$(jq -r '.top_holders_non_cex_pct // 0' "$CONC_JSON")
cluster_all=$(jq -r '.largest_cluster_all_pct // 0' "$CONC_JSON")
cluster_non_cex=$(jq -r '.largest_cluster_non_cex_pct // 0' "$CONC_JSON")
cluster_non_cex_dex_contract=$(jq -r '.largest_cluster_non_cex_dex_contract_pct // 0' "$CONC_JSON")
conc_snapshot=$(jq -r '.snapshot_date_utc // "-"' "$CONC_JSON")

risk_level="Medium"
if awk "BEGIN{exit !($cluster_non_cex >= 70)}"; then risk_level="Very High"
elif awk "BEGIN{exit !($cluster_non_cex >= 50)}"; then risk_level="High"
elif awk "BEGIN{exit !($cluster_non_cex >= 30)}"; then risk_level="Medium"
else risk_level="Low"; fi

trend_state="Neutral"
if awk "BEGIN{exit !($chg7 > 20 && $chg30 > 50)}"; then trend_state="Momentum Up"
elif awk "BEGIN{exit !($chg7 < -15 && $chg30 < -30)}"; then trend_state="Momentum Down"
fi

liquidity_ratio=$(awk "BEGIN{ if ($market_cap>0) printf \"%.4f\", $vol24/$market_cap; else print \"0\" }")
fdv_mcap=$(awk "BEGIN{ if ($market_cap>0) printf \"%.2f\", $fdv/$market_cap; else print \"0\" }")
cir_ratio=$(awk "BEGIN{ if ($max_supply>0) printf \"%.2f\", ($circulating/$max_supply)*100; else print \"0\" }")
unlock_overhang=$(awk "BEGIN{ if ($max_supply>0) printf \"%.2f\", (1-($circulating/$max_supply))*100; else print \"0\" }")

if [[ "$coin_id" != "unknown" && -f "$UNLOCK_PRESETS_JSON" ]]; then
  unlock_start=$(jq -r --arg id "$coin_id" '.[$id].start_date // empty' "$UNLOCK_PRESETS_JSON")
  unlock_months=$(jq -r --arg id "$coin_id" '.[$id].months // 0' "$UNLOCK_PRESETS_JSON")
  unlock_day=$(jq -r --arg id "$coin_id" '.[$id].unlock_day // 20' "$UNLOCK_PRESETS_JSON")
  if [[ -n "$unlock_start" && "$unlock_months" != "0" ]]; then
    UNLOCK_EVENT_STATUS="ok"
    if curl -fsS "${CURL_OPTS[@]}" -H 'accept: application/json' -H 'user-agent: Mozilla/5.0' "https://api.coingecko.com/api/v3/coins/${coin_id}/market_chart?vs_currency=usd&days=365&interval=daily" > /tmp/dy_jk_unlock_chart.json; then
      unlock_stats=$(COIN_ID="$coin_id" UNLOCK_START="$unlock_start" UNLOCK_MONTHS="$unlock_months" UNLOCK_DAY="$unlock_day" DATE_UTC="$DATE_UTC" python3 - <<'PY'
import json, datetime, statistics, os
coin_id=os.environ.get("COIN_ID")
start=datetime.date.fromisoformat(os.environ["UNLOCK_START"])
months=int(os.environ["UNLOCK_MONTHS"])
unlock_day=int(os.environ["UNLOCK_DAY"])
today=datetime.date.fromisoformat(os.environ["DATE_UTC"])
with open('/tmp/dy_jk_unlock_chart.json') as f:
    data=json.load(f)
if 'prices' not in data:
    print(json.dumps({"status":"chart_unavailable"}))
    raise SystemExit
prices=[(datetime.datetime.utcfromtimestamp(t/1000).date(),p) for t,p in data['prices']]
pm={d:p for d,p in prices}
def nearest(dt):
    for k in range(0,4):
        for d in (dt+datetime.timedelta(days=k), dt-datetime.timedelta(days=k)):
            if d in pm:
                return pm[d],d
    return None,None
dates=[]
for i in range(months):
    y=start.year + (start.month-1+i)//12
    m=(start.month-1+i)%12+1
    d=min(unlock_day, 28)
    ud=datetime.date(y,m,d)
    if ud <= today:
        dates.append(ud)
rows=[]
for ud in dates:
    p0,d0=nearest(ud)
    p_m7,d_m7=nearest(ud-datetime.timedelta(days=7))
    p_p7,d_p7=nearest(ud+datetime.timedelta(days=7))
    p_p14,d_p14=nearest(ud+datetime.timedelta(days=14))
    if None in (p0,p_m7,p_p7,p_p14):
        continue
    rows.append({
        "unlock": ud.isoformat(),
        "pre7": (p0/p_m7-1)*100,
        "post7": (p_p7/p0-1)*100,
        "post14": (p_p14/p0-1)*100
    })
if not rows:
    print(json.dumps({"status":"no_samples"}))
    raise SystemExit
pre=[r["pre7"] for r in rows]
post7=[r["post7"] for r in rows]
post14=[r["post14"] for r in rows]
last=rows[-1]
print(json.dumps({
    "status":"ok",
    "samples":len(rows),
    "avg_pre7":sum(pre)/len(pre),
    "avg_post7":sum(post7)/len(post7),
    "avg_post14":sum(post14)/len(post14),
    "neg_pre7":sum(1 for x in pre if x<0),
    "neg_post7":sum(1 for x in post7 if x<0),
    "neg_post14":sum(1 for x in post14 if x<0),
    "last_unlock":last["unlock"],
    "last_pre7":last["pre7"],
    "last_post7":last["post7"]
}))
PY
)
      stat_status=$(jq -r '.status // "unknown"' <<< "$unlock_stats")
      if [[ "$stat_status" == "ok" ]]; then
        unlock_samples=$(jq -r '.samples' <<< "$unlock_stats")
        unlock_avg_pre7=$(jq -r '.avg_pre7' <<< "$unlock_stats")
        unlock_avg_post7=$(jq -r '.avg_post7' <<< "$unlock_stats")
        unlock_avg_post14=$(jq -r '.avg_post14' <<< "$unlock_stats")
        unlock_neg_pre7=$(jq -r '.neg_pre7' <<< "$unlock_stats")
        unlock_neg_post7=$(jq -r '.neg_post7' <<< "$unlock_stats")
        unlock_neg_post14=$(jq -r '.neg_post14' <<< "$unlock_stats")
        unlock_last_date=$(jq -r '.last_unlock' <<< "$unlock_stats")
        unlock_last_pre7=$(jq -r '.last_pre7' <<< "$unlock_stats")
        unlock_last_post7=$(jq -r '.last_post7' <<< "$unlock_stats")
      else
        UNLOCK_EVENT_STATUS="$stat_status"
      fi
    else
      UNLOCK_EVENT_STATUS="chart_fetch_failed"
    fi
  fi
fi

cat <<DASH
================ DY-JK TOKEN DASHBOARD ================
Token: ${coin_name} (${symbol})
Chain/Address: ${CHAIN} / ${ADDRESS}
Snapshot (report UTC): ${DATE_UTC}
Snapshot (concentration UTC): ${conc_snapshot}

[1] Structure & Price
- Market rank: ${rank}
- Price (USD): ${price}
- Market cap (USD): ${market_cap}
- FDV (USD): ${fdv}
- Spot vol 24h (USD, aggregate): ${vol24}
- Return 7d/30d/1y: ${chg7}% / ${chg30}% / ${chg1y}%
- Trend regime: ${trend_state}

[2] Spot Liquidity (Exchange Sample)
- Tickers sampled: ${spot_ticker_count}
- Sampled spot volume sum (USD): ${spot_volume_sample}
- Top venues (sample):
$(jq -r '.[] | "  - " + .market + ": " + ((.vol|tostring))' <<< "$spot_top_venues")

[3] Derivatives
- Bitget perpetual symbol: ${deriv_symbol}
- Perp 24h quote volume: ${deriv_quote_vol}
- Funding rate: ${deriv_funding}
- Open interest/holding amount: ${deriv_oi}
- Mark / Index: ${deriv_mark} / ${deriv_index}
- Derivatives source status: ${DERIV_SOURCE_STATUS}

[4] Holder Structure (Advanced)
- Top${COUNT} coverage: ${top_cov}%
- Top${COUNT} non-CEX share: ${non_cex}%
- Largest linked cluster (all): ${cluster_all}%
- Largest linked cluster (non-CEX): ${cluster_non_cex}%
- Largest linked cluster (non-CEX/non-DEX/non-contract): ${cluster_non_cex_dex_contract}%
- Concentration risk level: ${risk_level}

[5] Unlock / Supply Pressure
- Circulating supply: ${circulating}
- Total supply: ${total_supply}
- Max supply: ${max_supply}
- Circulating ratio: ${cir_ratio}%
- Potential unlock overhang: ${unlock_overhang}%
- FDV/MCAP: ${fdv_mcap}x

[6] Unlock Event Backtest (pre7 / post7 / post14)
- Status: ${UNLOCK_EVENT_STATUS}
- Samples: ${unlock_samples}
- Avg pre7: ${unlock_avg_pre7}
- Avg post7: ${unlock_avg_post7}
- Avg post14: ${unlock_avg_post14}
- Negative count pre7/post7/post14: ${unlock_neg_pre7} / ${unlock_neg_post7} / ${unlock_neg_post14}
- Latest unlock window (${unlock_last_date}) pre7/post7: ${unlock_last_pre7} / ${unlock_last_post7}

[7] Risk Interpretation
- Liquidity proxy (24h vol / mcap): ${liquidity_ratio}
- If non-CEX linked cluster > 70%, treat as event-driven asset; use smaller size and faster invalidation.
- Watch cluster-to-CEX transfers as priority risk trigger.

[8] Data Source Health
- Market source status: ${MARKET_SOURCE_STATUS}
- Concentration source: /tmp/dy_jk_report.json
========================================================
DASH

if [[ -n "$OUT" ]]; then
  if [[ "$LANGUAGE" == "en" ]]; then
    printf "# %s (%s) Trade Report\n\n" "$coin_name" "$symbol" > "$OUT"
    printf "Use stdout dashboard for detailed fields.\n" >> "$OUT"
  else
    printf "# %s (%s) 交易报告\n\n" "$coin_name" "$symbol" > "$OUT"
    printf "详细字段已在命令行标准输出展示。\n" >> "$OUT"
  fi
fi
