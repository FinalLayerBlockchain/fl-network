#!/bin/bash
# Fee currency (gas paid in a token) end-to-end checks.  usage: fee_currency_e2e.sh <rpc>
RPC=${1:-http://127.0.0.1:8545}
K=${FL_KEYS_DIR:?set FL_KEYS_DIR to your key folder}
F=~/flbsc/bin/flpq; C=~/.foundry/bin/cast
T=~/flbsc/e2e; mkdir -p $T
DIR=0x0000000000000000000000000000000000005052
FLTD=0x0000000000000000000000000000000000005054
TRE=$($F address $K/treasury.json)
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }
bal() { $C call --rpc-url $RPC $FLTD "balanceOf(address)(uint256)" $1 | cut -d' ' -f1; }
supply() { $C call --rpc-url $RPC $FLTD "totalSupply()(uint256)" | cut -d' ' -f1; }

echo "== directory"
$C call --rpc-url $RPC $DIR "getCurrencies()(address[])"
$C call --rpc-url $RPC $DIR "getCurrencyConfigAndRate(address)(uint256,uint256,uint256)" $FLTD
[ "$($C call --rpc-url $RPC $FLTD 'symbol()(string)')" = '"FLTD"' ] && ok "FLTD symbol" || bad "FLTD symbol"
S0=$(supply); echo "supply $S0"

echo "== fresh wallet with 0 FL and 1,000 FLTD"
rm -f $T/fc1.json $T/fc2.json
W=$($F keygen $T/fc1.json); W2=$($F keygen $T/fc2.json)
$F tx $RPC $K/treasury.json $FLTD 0 $($C calldata "transfer(address,uint256)" $W 1000000000000000000000) >/dev/null && ok "treasury sent 1,000 FLTD" || bad "fund FLTD"
echo "W FL balance: $($F balance $RPC $W)"

echo "== token transfer paying gas in FLTD (sender has no FL)"
OUT=$($F --fee-currency $FLTD tx $RPC $T/fc1.json $FLTD 0 $($C calldata "transfer(address,uint256)" $W2 5000000000000000000) 2>&1); echo "$OUT"
H=$(echo "$OUT" | grep '^tx:' | awk '{print $2}')
echo "$OUT" | grep -q SUCCESS && ok "token-paid transfer succeeded" || bad "token-paid transfer"
RC=$($C receipt --rpc-url $RPC $H --json)
GU=$(echo $RC | python3 -c "import sys,json;print(int(json.load(sys.stdin)['gasUsed'],16))")
GP=$(echo $RC | python3 -c "import sys,json;print(int(json.load(sys.stdin)['effectiveGasPrice'],16))")
BN=$(echo $RC | python3 -c "import sys,json;print(int(json.load(sys.stdin)['blockNumber'],16))")
MINER=$($C block --rpc-url $RPC $BN -f miner)
FEE=$(python3 -c "print(($GU*$GP*1+99)//100)")
echo "gasUsed $GU price $GP miner $MINER expected token fee $FEE"
WB=$(bal $W); W2B=$(bal $W2)
MB=$(python3 -c "print($(bal $MINER) - $($C call --rpc-url $RPC --block $((BN-1)) $FLTD 'balanceOf(address)(uint256)' $MINER | cut -d' ' -f1))")
[ "$W2B" = "5000000000000000000" ] && ok "recipient got 5 FLTD" || bad "recipient $W2B"
[ "$(python3 -c "print(1000000000000000000000-5000000000000000000-$FEE)")" = "$WB" ] && ok "sender paid exactly value + fee in FLTD" || bad "sender balance $WB"
[ "$MB" = "$FEE" ] && ok "block producer received the FLTD fee" || bad "producer FLTD $MB (fee $FEE)"
[ "$(supply)" = "$S0" ] && ok "FLTD supply unchanged" || bad "supply $(supply)"
[ "$($F balance $RPC $W | cut -d' ' -f1)" = "0" ] && ok "sender still has 0 FL" || bad "sender FL"
TJ=$($C tx --rpc-url $RPC $H --json)
echo "$TJ" | grep -qi "\"feeCurrency\":\"$FLTD\"" && ok "RPC shows feeCurrency" || bad "feeCurrency missing in RPC tx"
[ "$(echo $RC | python3 -c "import sys,json;print(len(json.load(sys.stdin)['logs']))")" = "4" ] && ok "receipt has 4 logs (debit, transfer, refund, fee)" || bad "log count"

echo "== same transfer paying FL must fail (no FL)"
$F tx $RPC $T/fc1.json $FLTD 0 $($C calldata "transfer(address,uint256)" $W2 1) 2>&1 | tail -1 | grep -qi "insufficient funds" && ok "FL-paid rejected for 0-FL account" || bad "FL-paid not rejected"

echo "== unlisted fee currency is rejected"
$F --fee-currency 0x0000000000000000000000000000000000005055 tx $RPC $T/fc1.json $FLTD 0 $($C calldata "transfer(address,uint256)" $W2 1) 2>&1 | tail -1 | grep -qi "fee currency not allowed" && ok "unlisted token rejected" || bad "unlisted token"

echo "== an account with no FLTD cannot pay gas in FLTD"
rm -f $T/fc3.json; W3=$($F keygen $T/fc3.json)
$F send $RPC $K/treasury.json $W3 1 >/dev/null
$F --fee-currency $FLTD send $RPC $T/fc3.json $W 0.5 2>&1 | tail -1 | grep -qi "insufficient funds" && ok "zero-FLTD account rejected by the pool" || bad "zero-FLTD account not rejected"

echo "== FL value + FLTD gas from the treasury"
TB=$($F balance $RPC $TRE | cut -d' ' -f1)
$F --fee-currency $FLTD send $RPC $K/treasury.json $W 3 | grep -q SUCCESS && ok "FL send with FLTD gas" || bad "FL send with FLTD gas"
[ "$($F balance $RPC $W | cut -d' ' -f1)" = "3" ] && ok "recipient got 3 FL" || bad "recipient FL $($F balance $RPC $W)"
echo "treasury FL before $TB after $($F balance $RPC $TRE)"

echo "== RESULT: $pass passed, $fail failed"
