#!/bin/bash
C=~/.foundry/bin/cast; RPC=${1:-http://127.0.0.1:8545}
BN=$($C block-number --rpc-url $RPC)
echo "head $BN"
for b in $(seq $((BN-29)) $BN); do $C block $b --rpc-url $RPC -f miner; done | sort | uniq -c
$C call --rpc-url $RPC 0x0000000000000000000000000000000000001000 'getMiningValidators()(address[],bytes[])' | head -1
B=$($C block $BN --rpc-url $RPC --json)
echo "$B" | python3 -c "import sys,json;b=json.load(sys.stdin);print('extraData bytes',(len(b['extraData'])-2)//2,'difficulty',int(b['difficulty'],16))"
