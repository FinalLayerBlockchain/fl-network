#!/bin/bash
RPC=${1:-http://127.0.0.1:8545}
C=~/.foundry/bin/cast
SH=0x0000000000000000000000000000000000002002
BN=$($C block-number --rpc-url $RPC)
echo "block $BN time $($C block $BN --rpc-url $RPC -f timestamp)"
echo "lastInflationTime $($C call --rpc-url $RPC $SH 'lastInflationTime()(uint256)')"
for i in 1 2 3; do
  OP=$(~/flbsc/bin/flpq address ${FL_KEYS_DIR:?set FL_KEYS_DIR to your key folder}/val$i-operator.json)
  CR=$($C call --rpc-url $RPC $SH 'getValidatorCreditContract(address)(address)' $OP)
  echo "val$i credit $CR pooled $($C call --rpc-url $RPC $CR 'totalPooledBNB()(uint256)') opShares $($C call --rpc-url $RPC $CR 'balanceOf(address)(uint256)' $OP)"
done
echo "stakehub balance $($C balance --rpc-url $RPC $SH)"
