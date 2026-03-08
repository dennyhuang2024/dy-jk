#!/usr/bin/env bash
set -euo pipefail

ADDRESS=""
CHAIN="solana"
DATE_UTC="$(date -u +%F)"
COUNT="250"
API_BASE="https://api.bubblemaps.io"
VALIDATION_SECRET="${BM_VALIDATION_SECRET:-LTJBO6Dsb5dEJ9pS}"
PROXY="${DY_JK_PROXY:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --address) ADDRESS="$2"; shift 2 ;;
    --chain) CHAIN="$2"; shift 2 ;;
    --date) DATE_UTC="$2"; shift 2 ;;
    --count) COUNT="$2"; shift 2 ;;
    --api-base) API_BASE="$2"; shift 2 ;;
    --validation-secret) VALIDATION_SECRET="$2"; shift 2 ;;
    --proxy) PROXY="$2"; shift 2 ;;
    -h|--help)
      cat <<USAGE
Usage: verify_concentration.sh --address <TOKEN_ADDRESS> [--chain solana] [--date YYYY-MM-DD] [--count 250] [--proxy http://127.0.0.1:7897]
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

for cmd in curl jq node; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing dependency: $cmd" >&2; exit 1; }
done

TOP_PATH="/addresses/token-top-holders?count=${COUNT}&date=${DATE_UTC}&nocache=false"
SUB_PATH="/relationships/subgraph?whitelist_token_address=${ADDRESS}&whitelist_token_chain=${CHAIN}"

build_token() {
  local path="$1"
  node -e '
const crypto=require("crypto");
const b=s=>Buffer.from(s).toString("base64url");
const path=process.argv[1];
const secret=process.argv[2];
const h=b(JSON.stringify({alg:"HS256",typ:"JWT"}));
const p=b(JSON.stringify({data:path,exp:Math.floor(Date.now()/1000)+300}));
const s=crypto.createHmac("sha256",secret).update(`${h}.${p}`).digest("base64url");
process.stdout.write(`${h}.${p}.${s}`);
' "$path" "$VALIDATION_SECRET"
}

TOP_TOKEN="$(build_token "$TOP_PATH")"
CURL_OPTS=()
if [[ -n "$PROXY" ]]; then
  CURL_OPTS+=(--proxy "$PROXY")
fi

curl -s ${CURL_OPTS[@]+"${CURL_OPTS[@]}"} "${API_BASE}${TOP_PATH}" \
  -H "X-Validation: ${TOP_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "{\"chain\":\"${CHAIN}\",\"address\":\"${ADDRESS}\"}" \
  > /tmp/dy_jk_top_holders.json

jq -r '.[].address' /tmp/dy_jk_top_holders.json | jq -Rsc 'split("\n")[:-1]' > /tmp/dy_jk_address_list.json

SUB_TOKEN="$(build_token "$SUB_PATH")"

curl -s ${CURL_OPTS[@]+"${CURL_OPTS[@]}"} "${API_BASE}${SUB_PATH}" \
  -H "X-Validation: ${SUB_TOKEN}" \
  -H "Content-Type: application/json" \
  --data @/tmp/dy_jk_address_list.json \
  > /tmp/dy_jk_subgraph.json

node - <<'NODE'
const fs=require('fs');
const holders=JSON.parse(fs.readFileSync('/tmp/dy_jk_top_holders.json','utf8'));
const rels=JSON.parse(fs.readFileSync('/tmp/dy_jk_subgraph.json','utf8'));

const shareByAddr=new Map();
const detailByAddr=new Map();
const addrSet=new Set();
for(const h of holders){
  addrSet.add(h.address);
  shareByAddr.set(h.address,h.holder_data.share||0);
  detailByAddr.set(h.address,h.address_details||{});
}

const graph=new Map();
for(const a of addrSet) graph.set(a,new Set());
for(const r of rels){
  const a=r.from_address,b=r.to_address;
  if(addrSet.has(a)&&addrSet.has(b)&&a!==b){
    graph.get(a).add(b);
    graph.get(b).add(a);
  }
}

function sumShares(pred){
  let s=0;
  for(const h of holders){
    if(pred(h.address_details||{})) s += (h.holder_data.share||0);
  }
  return s;
}

const components=[];
const seen=new Set();
for(const a of addrSet){
  if(seen.has(a)) continue;
  const stack=[a];
  seen.add(a);
  const nodes=[];
  while(stack.length){
    const x=stack.pop();
    nodes.push(x);
    for(const y of graph.get(x)){
      if(!seen.has(y)){
        seen.add(y);
        stack.push(y);
      }
    }
  }
  let all=0, nonCex=0, nonCexDex=0, nonCexDexContract=0;
  for(const n of nodes){
    const d=detailByAddr.get(n)||{};
    const sh=shareByAddr.get(n)||0;
    all += sh;
    if(!d.is_cex) nonCex += sh;
    if(!d.is_cex && !d.is_dex) nonCexDex += sh;
    if(!d.is_cex && !d.is_dex && !d.is_contract) nonCexDexContract += sh;
  }
  components.push({nodes:nodes.length,all,nonCex,nonCexDex,nonCexDexContract});
}

const best=(k)=>components.reduce((m,c)=>!m||c[k]>m[k]?c:m,null);
const report={
  snapshot_date_utc: new Date().toISOString(),
  holder_count: holders.length,
  component_count: components.length,
  top_holders_coverage_pct: (sumShares(()=>true)*100),
  top_holders_cex_pct: (sumShares(d=>d.is_cex===true)*100),
  top_holders_non_cex_pct: (sumShares(d=>d.is_cex!==true)*100),
  largest_cluster_all_pct: ((best('all')?.all||0)*100),
  largest_cluster_non_cex_pct: ((best('nonCex')?.nonCex||0)*100),
  largest_cluster_non_cex_dex_pct: ((best('nonCexDex')?.nonCexDex||0)*100),
  largest_cluster_non_cex_dex_contract_pct: ((best('nonCexDexContract')?.nonCexDexContract||0)*100)
};

fs.writeFileSync('/tmp/dy_jk_report.json', JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
NODE
