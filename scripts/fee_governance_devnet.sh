#!/bin/bash
# Validator listing / suspension checks on a 3-validator devnet. usage: fee_governance_devnet.sh <rpc>
RPC=${1:-http://127.0.0.1:8545}
K=${FL_KEYS_DIR:?set FL_KEYS_DIR to your key folder}
F=~/flbsc/bin/flpq; C=~/.foundry/bin/cast
DIR=0x0000000000000000000000000000000000005052; ORA=0x0000000000000000000000000000000000005053; FLTD=0x0000000000000000000000000000000000005054
SRC=${FL_CONTRACTS_DIR:-../fl-genesis-contracts}
pass=0; fail=0; ok() { echo "PASS: $1"; pass=$((pass+1)); }; bad() { echo "FAIL: $1"; fail=$((fail+1)); }
echo "validators: $($C call --rpc-url $RPC 0x0000000000000000000000000000000000001000 'getValidators()(address[])')"
for i in 1 2 3; do A=$($F address $K/val$i-consensus.json); [ "$($F balance $RPC $A | cut -d' ' -f1)" = "0" ] && $F send $RPC $K/treasury.json $A 10 >/dev/null; done

echo "== deploy an unlisted token and have 2 of 3 validators approve listing it"
BC=$(python3 -c "import json;o=json.load(open('$SRC/out/FeeCurrencyERC20.sol/FLTestDollar.json'));print(o['bytecode']['object'])")
NEW=$($F tx $RPC $K/treasury.json create 0 $BC 2>&1 | grep contract: | awk '{print $2}'); echo "new token $NEW"
CD=$($C calldata "validatorSetConfig(address,address,uint256,uint128,uint128,uint64)" $NEW $ORA 50000 1 50 0)
$F tx $RPC $K/val1-consensus.json $DIR 0 $CD | grep -q SUCCESS && ok "val1 approved" || bad "val1 approve"
$F tx $RPC $K/val1-consensus.json $DIR 0 $CD 2>&1 | tail -1 | grep -qi "already approved\|revert" && ok "double approval refused" || bad "double approval"
$F tx $RPC $K/val2-consensus.json $DIR 0 $CD | grep -q SUCCESS && ok "val2 approved (2 of 3)" || bad "val2 approve"
NONCE=$($C call --rpc-url $RPC $DIR "tokenNonce(address)(uint256)" $NEW)
ID=$($C keccak $($C abi-encode "f(uint8,address,address,uint256,uint128,uint128,uint64,uint256)" 2 $NEW $ORA 50000 1 50 0 $NONCE))
ACT=$($C call --rpc-url $RPC $DIR "getAction(bytes32)(uint8,address,uint256,bool,uint256,uint256)" $ID); echo "$ACT" | tr '\n' ' '; echo
READY=$(echo "$ACT" | sed -n 3p | cut -d' ' -f1); NOW=$(date +%s)
[ "$READY" -gt $((NOW+86000)) ] && ok "listing waits about 1 day (readyAt $READY)" || bad "readyAt $READY"
$F tx $RPC $K/treasury.json $DIR 0 $($C calldata "executeValidatorAction(bytes32)" $ID) 2>&1 | tail -1 | grep -qi "revert\|not ready" && ok "cannot execute before the wait" || bad "executed early"
$C call --rpc-url $RPC $DIR "getCurrencyConfigAndRate(address)(uint256,uint256,uint256)" $NEW >/dev/null 2>&1 && bad "listed early" || ok "token not listed yet"

echo "== emergency suspend of FLTD by 2 of 3 validators"
SD=$($C calldata "validatorSuspend(address)" $FLTD)
$F tx $RPC $K/val1-consensus.json $DIR 0 $SD | grep -q SUCCESS && ok "val1 suspend vote" || bad "val1 suspend"
[ "$($C call --rpc-url $RPC $DIR 'suspended(address)(bool)' $FLTD)" = "false" ] && ok "1 of 3 is not enough" || bad "suspended with 1 vote"
$F tx $RPC $K/val3-consensus.json $DIR 0 $SD | grep -q SUCCESS && ok "val3 suspend vote" || bad "val3 suspend"
[ "$($C call --rpc-url $RPC $DIR 'suspended(address)(bool)' $FLTD)" = "true" ] && ok "FLTD suspended immediately at 2 of 3" || bad "not suspended"
W=$($F address $K/treasury.json)
$F --fee-currency $FLTD send $RPC $K/treasury.json $W 1 2>&1 | tail -1 | grep -qi "not allowed\|suspended" && ok "gas in suspended FLTD rejected" || bad "suspended token still pays gas"
$F tx $RPC $K/treasury.json $FLTD 0 $($C calldata "transfer(address,uint256)" 0x00000000000000000000000000000000000000aa 1) | grep -q SUCCESS && ok "FLTD itself still transferable (gas in FL)" || bad "FLTD transfer"
echo "== non-validator cannot act"
$F tx $RPC $K/treasury.json $DIR 0 $SD 2>&1 | tail -1 | grep -qi "revert\|validator" && ok "treasury cannot vote as validator" || bad "treasury voted"
echo "== RESULT: $pass passed, $fail failed"
