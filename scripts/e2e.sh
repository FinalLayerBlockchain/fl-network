#!/bin/bash
# End-to-end checks against a running Final Layer node.  usage: e2e.sh <rpc>
RPC=${1:-http://127.0.0.1:8545}
K=${FL_KEYS_DIR:?set FL_KEYS_DIR to your key folder}
F=~/flbsc/bin/flpq
T=~/flbsc/e2e; mkdir -p $T
addr() { $F address $1; }
TRE=$(addr $K/treasury.json)
echo "== chain id: $(curl -s -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' $RPC)"
echo "== treasury $TRE"; $F balance $RPC $TRE

echo "== fund the 3 validator operators (100,010 FL each)"
for i in 1 2 3; do
  OP=$(addr $K/val$i-operator.json)
  [ "$($F balance $RPC $OP | cut -d' ' -f1)" = "0" ] && { $F send $RPC $K/treasury.json $OP 100010 || exit 1; }
done

echo "== ECDSA-signed transaction must be rejected"
ECKEY=${FL_E2E_ECKEY:?set FL_E2E_ECKEY to a funded devnet-only secp256k1 key}
ECADDR=$(~/.foundry/bin/cast wallet address $ECKEY)
$F send $RPC $K/treasury.json $ECADDR 5 >/dev/null && echo "funded ECDSA test address $ECADDR with 5 FL"
~/.foundry/bin/cast send --rpc-url $RPC --private-key $ECKEY --legacy --gas-limit 21000 --gas-price 1000000000 0x000000000000000000000000000000000000dEaD --value 1 2>&1 | tail -2
~/.foundry/bin/cast send --rpc-url $RPC --private-key $ECKEY --gas-limit 21000 --gas-price 1000000000 --priority-gas-price 1000000000 0x000000000000000000000000000000000000dEaD --value 1 2>&1 | tail -2

echo "== key rotation on a fresh test wallet"
rm -f $T/w1.json $T/w2.json $T/attacker.json
W=$($F keygen $T/w1.json); $F keygen $T/w2.json >/dev/null; $F keygen $T/attacker.json >/dev/null
$F send $RPC $K/treasury.json $W 10 || exit 1
$F registry $RPC $W
$F rotate $RPC $T/w1.json $T/w2.json || exit 1
$F registry $RPC $W
echo "-- old key must now fail:"; $F send $RPC $T/w1.json $TRE 1 --from $W 2>&1 | tail -1
echo "-- attacker key must fail:"; $F send $RPC $T/attacker.json $TRE 1 --from $W 2>&1 | tail -1
echo "-- new key spends from the same address:"; $F send $RPC $T/w2.json $TRE 1 --from $W || exit 1
$F balance $RPC $W

echo "== register validators in StakeHub (100,000 FL self-stake each)"
for i in 1 2 3; do
  $F create-validator $RPC $K/val$i-operator.json $K/val$i-consensus.json 100000 FLVal$i 1000 || exit 1
done
echo "== StakeHub params"
for sel in "stakingAprBps()" "validatorRewardBps()" "lastInflationTime()" "maxElectedValidators()"; do
  echo "$sel = $(~/.foundry/bin/cast call --rpc-url $RPC 0x0000000000000000000000000000000000002002 "$sel(uint256)" 2>/dev/null || ~/.foundry/bin/cast call --rpc-url $RPC 0x0000000000000000000000000000000000002002 "$sel" | ~/.foundry/bin/cast to-dec)"
done
NOW=$(date +%s)
echo "pending inflation for +1 day: $(~/.foundry/bin/cast call --rpc-url $RPC 0x0000000000000000000000000000000000002002 'pendingStakingInflation(uint256)(uint256)' $((NOW+86400)))"
