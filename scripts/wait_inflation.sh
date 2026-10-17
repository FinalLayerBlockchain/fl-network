#!/bin/bash
C=~/.foundry/bin/cast; SH=0x0000000000000000000000000000000000002002; RPC=http://127.0.0.1:8545
START=$($C call --rpc-url $RPC $SH 'lastInflationTime()(uint256)' | cut -d' ' -f1)
for i in $(seq 1 120); do
  NOW=$($C call --rpc-url $RPC $SH 'lastInflationTime()(uint256)' | cut -d' ' -f1)
  [ "$NOW" != "$START" ] && break
  sleep 5
done
echo "lastInflationTime $START -> $NOW"
bash ${FL_NETWORK_DIR:-.}/scripts/inflation_probe.sh
# find the breathe block and its events
BN=$($C block-number --rpc-url $RPC)
for b in $(seq $((BN-40)) $BN); do
  T=$($C block $b --rpc-url $RPC -f timestamp)
  if [ "$T" -ge "$NOW" ] && [ "$T" -le "$NOW" ]; then echo "breathe block $b"; BB=$b; fi
done
$C logs --rpc-url $RPC --from-block $BB --to-block $BB --address $SH 'StakingInflationDistributed(uint256,uint256)' | grep -E "data|blockNumber"
grep -h "Staking inflation minted" ~/flbsc/net/node*/node.log | tail -3
